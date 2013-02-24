# pattern-match.rb
#
# Copyright (C) 2012-2013 Kazuki Tsujimoto, All rights reserved.

require 'pattern-match/version'

module PatternMatch
  module Deconstructable
    def call(*subpatterns)
      if Object == self
        raise MalformedPatternError unless subpatterns.length == 1
        PatternObject.new(subpatterns[0])
      elsif Hash == self
        raise MalformedPatternError unless subpatterns.length == 1
        PatternHash.new(subpatterns[0])
      else
        PatternDeconstructor.new(self, *subpatterns)
      end
    end
  end

  class Pattern
    attr_accessor :parent, :next, :prev

    def initialize(*subpatterns)
      @parent = nil
      @next = nil
      @prev = nil
      @subpatterns = subpatterns.map {|i| i.kind_of?(Pattern) ? i : PatternValue.new(i) }
      set_subpatterns_relation
    end

    def vars
      @subpatterns.map(&:vars).flatten
    end

    def binding
      vars.each_with_object({}) {|v, h| h[v.name] = v.val }
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
      @next.kind_of?(PatternQuantifier) || (root? ? false : @parent.quantified?)
    end

    def root?
      @parent == nil
    end

    def validate
      if root?
        dup_vars = vars - vars.uniq(&:name)
        unless dup_vars.empty?
          raise MalformedPatternError, "duplicate variables: #{dup_vars.map(&:name).join(', ')}"
        end
      end
      raise MalformedPatternError if @subpatterns.count {|i| i.kind_of?(PatternQuantifier) } > 1
      @subpatterns.each(&:validate)
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
      super(*spec.values)
      @spec = spec.map {|k, pat| [k.to_proc, pat] }
    rescue
      raise MalformedPatternError
    end

    def match(val)
      @spec.all? {|k, pat| pat.match(k.(val)) rescue raise PatternNotMatch }
    end
  end

  class PatternHash < Pattern
    def initialize(spec)
      super(*spec.values)
      @spec = spec
    end

    def match(val)
      raise PatternNotMatch unless val.kind_of?(Hash)
      raise PatternNotMatch unless @spec.keys.all? {|k| val.has_key?(k) }
      @spec.all? {|k, pat| pat.match(val[k]) rescue raise PatternNotMatch }
    end
  end

  class PatternDeconstructor < Pattern
    def initialize(deconstructor, *subpatterns)
      super(*subpatterns)
      @deconstructor = deconstructor
    end

    def match(val)
      deconstructed_vals = @deconstructor.deconstruct(val)
      k = deconstructed_vals.length - (@subpatterns.length - 2)
      quantifier = @subpatterns.find {|i| i.kind_of?(PatternQuantifier) }
      if quantifier
        return false unless quantifier.min_k <= k
      else
        return false unless @subpatterns.length == deconstructed_vals.length
      end
      @subpatterns.flat_map do |pat|
        case
        when pat.next.kind_of?(PatternQuantifier)
          []
        when pat.kind_of?(PatternQuantifier)
          pat.prev.vars.each {|v| v.set_bind_to(pat) }
          Array.new(k, pat.prev)
        else
          [pat]
        end
      end.zip(deconstructed_vals).all? do |pat, v|
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
      raise MalformedPatternError unless @parent.kind_of?(PatternDeconstructor)
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
      qs = ancestors.map {|i| i.next.kind_of?(PatternQuantifier) ? i.next : nil }.find_all {|i| i }.reverse
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
      pat = pat_or_val.kind_of?(Pattern) ? pat_or_val : PatternValue.new(pat_or_val)
      pat.validate
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
        class << uscore
          def [](*args)
            Array.call(*args)
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
            @stacks[name].pop
            if @stacks[name].empty?
              remove_method(name)
            end
          end
        end
      end
    end

    class TmpBindingModule < ::Module
    end

    def tmpbinding_module(obj)
      m = obj.singleton_class.ancestors.find {|i| i.kind_of?(TmpBindingModule) }
      unless m
        m = TmpBindingModule.new
        m.instance_eval do
          @stacks = ::Hash.new {|h, k| h[k] = [] }
        end
        obj.singleton_class.class_eval do
          if respond_to?(:prepend, true)
            prepend m
          else
            include m
          end
        end
      end
      m
    end
  end

  class PatternNotMatch < Exception; end
  class PatternMatchError < StandardError; end
  class NoMatchingPatternError < PatternMatchError; end
  class MalformedPatternError < PatternMatchError; end

  # Make Pattern and its subclasses/Env private.
  if respond_to?(:private_constant)
    constants.each do |c|
      klass = const_get(c)
      next unless klass.kind_of?(Class)
      if klass <= Pattern
        private_constant c
      end
    end
    private_constant :Env
  end
end

module Kernel
  private

  def match(*vals, &block)
    do_match = Proc.new do |val|
      env = PatternMatch.const_get(:Env).new(self, val)
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

class Class
  include PatternMatch::Deconstructable

  def deconstruct(val)
    raise NotImplementedError, "need to define `#{__method__}'"
  end

  private

  def accept_self_instance_only(val)
    raise PatternMatch::PatternNotMatch unless val.kind_of?(self)
  end
end

class << Array
  def deconstruct(val)
    accept_self_instance_only(val)
    val
  end
end

class << Struct
  def deconstruct(val)
    accept_self_instance_only(val)
    val.values
  end
end

class << Complex
  def deconstruct(val)
    accept_self_instance_only(val)
    val.rect
  end
end

class << Rational
  def deconstruct(val)
    accept_self_instance_only(val)
    [val.numerator, val.denominator]
  end
end

class << MatchData
  def deconstruct(val)
    accept_self_instance_only(val)
    val.captures.empty? ? [val[0]] : val.captures
  end
end

class Regexp
  include PatternMatch::Deconstructable

  def deconstruct(val)
    m = Regexp.new("\\A#{source}\\z", options).match(val.to_s)
    raise PatternMatch::PatternNotMatch unless m
    m.captures.empty? ? [m[0]] : m.captures
  end
end

class Symbol
  def call(*args)
    Proc.new {|obj| obj.__send__(self, *args) }
  end
end
