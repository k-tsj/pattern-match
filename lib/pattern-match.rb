# pattern-match.rb
#
# Copyright (C) 2012 Kazuki Tsujimoto, All rights reserved.

require 'pattern-match/version'

module PatternMatch
  if Module.private_method_defined? :refine
    SUPPORT_REFINEMENTS = true
  else
    SUPPORT_REFINEMENTS = false
    Module.module_eval do
      private

      def refine(klass, &block)
        klass.class_eval(&block)
      end

      def using(klass)
      end
    end
  end

  module Deconstructable
    def call(*subpatterns)
      if Object == self
        raise MalformedPatternError unless subpatterns.length == 1
        PatternObject.new(subpatterns[0])
      else
        PatternExtractor.new(self, *subpatterns)
      end
    end

    if SUPPORT_REFINEMENTS
      alias [] call
    end
  end

  module NameSpace
    refine Class do
      include Deconstructable

      def deconstruct(val)
        raise NotImplementedError, "need to define `#{__method__}'"
      end

      private

      def accept_self_instance_only(val)
        raise PatternNotMatch unless val.is_a?(self)
      end
    end

    refine Array.singleton_class do
      def deconstruct(val)
        accept_self_instance_only(val)
        val
      end
    end

    refine Struct.singleton_class do
      def deconstruct(val)
        accept_self_instance_only(val)
        val.values
      end
    end

    refine Complex.singleton_class do
      def deconstruct(val)
        accept_self_instance_only(val)
        val.rect
      end
    end

    refine Rational.singleton_class do
      def deconstruct(val)
        accept_self_instance_only(val)
        [val.numerator, val.denominator]
      end
    end

    refine MatchData.singleton_class do
      def deconstruct(val)
        accept_self_instance_only(val)
        val.captures.empty? ? [val[0]] : val.captures
      end
    end

    if SUPPORT_REFINEMENTS
      def Struct.method_added(name)
        if name == members[0]
          this = self
          PatternMatch::NameSpace.module_eval do
            refine this.singleton_class do
              include Deconstructable
            end
          end
        end
      end

      refine Proc do
        include Deconstructable

        def deconstruct(val)
          [self === val]
        end
      end

      refine Symbol do
        include Deconstructable

        def deconstruct(val)
          [self.to_proc === val]
        end
      end
    end

    refine Symbol do
      def call(*args)
        Proc.new {|obj| obj.__send__(self, *args) }
      end
    end

    refine Regexp do
      include Deconstructable

      def deconstruct(val)
        m = Regexp.new("\\A#{source}\\z", options).match(val.to_s)
        raise PatternNotMatch unless m
        m.captures.empty? ? [m[0]] : m.captures
      end
    end
  end

  class Pattern
    attr_accessor :parent, :next, :prev
    attr_writer :pattern_match_env

    def initialize(*subpatterns)
      @parent = nil
      @next = nil
      @prev = nil
      @pattern_match_env = nil
      @subpatterns = subpatterns.map {|i| i.is_a?(Pattern) ? i : PatternValue.new(i) }
      set_subpatterns_relation
    end

    def vars
      @vars ||= @subpatterns.map(&:vars).flatten
    end

    def binding
      @binding ||= vars.each_with_object({}) {|v, h| h[v.name] = v.val }
    end

    def &(pattern)
      PatternAnd.new(self, pattern)
    end

    def |(pattern)
      PatternOr.new(self, pattern)
    end

    def !@
      PatternNot.new(self)
    end

    def to_a
      [self, PatternQuantifier.new(0)]
    end

    def quantified?
      @next.is_a?(PatternQuantifier) || (root? ? false : @parent.quantified?)
    end

    def root?
      @parent == nil
    end

    def validate
      if root?
        dup_vars = vars - vars.uniq {|i| i.name }
        raise MalformedPatternError, "duplicate variables: #{dup_vars.map(&:name).join(', ')}" unless dup_vars.empty?
      end
      raise MalformedPatternError if @subpatterns.count {|i| i.is_a?(PatternQuantifier) } > 1
      @subpatterns.each(&:validate)
    end

    def pattern_match_env
      @pattern_match_env || @parent.pattern_match_env
    end

    private

    def set_subpatterns_relation
      @subpatterns.each do |i|
        i.parent = self
      end
      @subpatterns.each_cons(2) do |a, b|
        a.next = b
        b.prev = a
      end
    end

    def ancestors
      ary = []
      pat = self
      until pat == nil
        ary << pat
        pat = pat.parent
      end
      ary
    end
  end

  class PatternObject < Pattern
    def initialize(spec)
      raise MalformedPatternError unless spec.is_a?(Hash)
      super(*spec.values)
      @spec = spec.map {|k, pat| [k.to_proc, pat] }
    rescue
      raise MalformedPatternError
    end

    def match(val)
      @spec.all? {|k, pat| pat.match(k.(val)) rescue raise PatternNotMatch }
    end
  end

  class PatternExtractor < Pattern
    def initialize(extractor, *subpatterns)
      super(*subpatterns)
      @extractor = extractor
    end

    def match(val)
      extracted_vals = pattern_match_env.call_refined_method(@extractor, :deconstruct, val)
      k = extracted_vals.length - (@subpatterns.length - 2)
      quantifier = @subpatterns.find {|i| i.is_a?(PatternQuantifier) }
      if quantifier
        return false unless quantifier.min_k <= k
      else
        return false unless @subpatterns.length == extracted_vals.length
      end
      @subpatterns.flat_map do |pat|
        case
        when pat.next.is_a?(PatternQuantifier)
          []
        when pat.is_a?(PatternQuantifier)
          pat.prev.vars.each {|v| v.set_bind_to(pat) }
          Array.new(k, pat.prev)
        else
          [pat]
        end
      end.zip(extracted_vals).all? do |pat, v|
        pat.match(v)
      end
    end
  end

  class PatternQuantifier < Pattern
    attr_reader :min_k

    def initialize(min_k)
      super()
      @min_k = min_k
    end

    def match(val)
      raise PatternMatchError, 'must not happen'
    end

    def validate
      super
      raise MalformedPatternError unless @prev
      raise MalformedPatternError unless @parent.is_a?(PatternExtractor)
    end
  end

  class PatternVariable < Pattern
    attr_reader :name, :val

    def initialize(name)
      super()
      @name = name
      @val = nil
      @bind_to = nil
    end

    def match(val)
      bind(val)
      true
    end

    def vars
      [self]
    end

    def set_bind_to(quantifier)
      if @val
        outer = @val
        (nest_level(quantifier) - 1).times do
          outer = outer[-1]
        end
        @bind_to = []
        outer << @bind_to
      else
        @val = @bind_to = []
      end
    end

    private

    def bind(val)
      if quantified?
        @bind_to << val
      else
        @val = val
      end
    end

    def nest_level(quantifier)
      qs = ancestors.map {|i| i.next.is_a?(PatternQuantifier) ? i.next : nil }.find_all {|i| i }.reverse
      qs.index(quantifier) || (raise PatternMatchError)
    end
  end

  class PatternValue < Pattern
    def initialize(val, compare_by = :===)
      super()
      @val = val
      @compare_by = compare_by
    end

    def match(val)
      @val.__send__(@compare_by, val)
    end
  end

  class PatternAnd < Pattern
    def match(val)
      @subpatterns.all? {|i| i.match(val) }
    end
  end

  class PatternOr < Pattern
    def match(val)
      @subpatterns.find do |i|
        begin
          i.match(val)
        rescue PatternNotMatch
          false
        end
      end
    end

    def validate
      super
      raise MalformedPatternError unless vars.length == 0
    end
  end

  class PatternNot < Pattern
    def match(val)
      ! @subpatterns[0].match(val)
    rescue PatternNotMatch
      true
    end

    def validate
      super
      raise MalformedPatternError unless vars.length == 0
    end
  end

  class Env < BasicObject
    def initialize(ctx, val)
      @ctx = ctx
      @val = val
    end

    private

    def with(pat_or_val, guard_proc = nil, &block)
      pat = pat_or_val.is_a?(Pattern) ? pat_or_val : PatternValue.new(pat_or_val)
      pat.validate
      pat.pattern_match_env = self
      if pat.match(@val) and (guard_proc ? with_tmpbinding(@ctx, pat.binding, &guard_proc) : true)
        ret = with_tmpbinding(@ctx, pat.binding, &block)
        ::Kernel.throw(:exit_match, ret)
      else
        nil
      end
    rescue PatternNotMatch
    end

    def guard(&block)
      block
    end

    def method_missing(name, *)
      case name.to_s
      when '___'
        PatternQuantifier.new(0)
      when /\A__(\d+)\z/
        PatternQuantifier.new($1.to_i)
      else
        PatternVariable.new(name)
      end
    end

    def _(*vals)
      case vals.length
      when 0
        uscore = PatternVariable.new(:_)
        uscore.pattern_match_env = self
        class << uscore
          def [](*args)
            pattern_match_env.call_refined_method(::Array, :call, *args)
          end

          def match(val)
            true
          end

          def vars
            []
          end
        end
        uscore
      when 1
        PatternValue.new(vals[0])
      when 2
        PatternValue.new(vals[0], vals[1])
      else
        raise MalformedPatternError
      end
    end

    alias __ _
    alias _l _

    def with_tmpbinding(obj, binding, &block)
      tmpbinding_module(obj).instance_eval do
        begin
          binding.each do |name, val|
            stack = @stacks[name]
            if stack.empty?
              define_method(name) { stack[-1] }
              private name
            end
            stack.push(val)
          end
          obj.instance_eval(&block)
        ensure
          binding.each do |name, _|
            if @stacks[name].tap(&:pop).empty?
              remove_method(name)
            end
          end
        end
      end
    end

    class TmpBindingModule < ::Module
    end

    def tmpbinding_module(obj)
      m = obj.singleton_class.ancestors.find {|i| i.is_a? TmpBindingModule }
      unless m
        m = TmpBindingModule.new
        m.instance_eval do
          @stacks = ::Hash.new {|h, k| h[k] = [] }
        end
        obj.extend(m)
      end
      m
    end
  end

  class PatternNotMatch < Exception; end
  class PatternMatchError < StandardError; end
  class NoMatchingPatternError < PatternMatchError; end
  class MalformedPatternError < PatternMatchError; end
end

module Kernel
  private

  def match(*vals, &block)
    do_match = Proc.new do |val|
      env = PatternMatch::Env.new(self, val)
      class << env
        using ::PatternMatch::NameSpace

        def call_refined_method(obj, name, *args)
          obj.__send__(name, *args)
        end
      end
      catch(:exit_match) do
        env.instance_eval(&block)
        raise ::PatternMatch::NoMatchingPatternError
      end
    end
    case vals.length
    when 0
      do_match
    when 1
      do_match.(vals[0])
    else
      raise ArgumentError, "wrong number of arguments (#{vals.length} for 0..1)"
    end
  end
end
