# pattern-match.rb
#
# Copyright (C) 2012-2013 Kazuki Tsujimoto, All rights reserved.

require 'pattern-match/version'

module PatternMatch
  module Deconstructable
    def call(*subpatterns)
      if Object == self
        PatternKeywordArgStyleDeconstructor.new(Object, :respond_to?, :__send__, *subpatterns)
      else
        pattern_matcher(*subpatterns)
      end
    end
  end

  class ::Object
    def pattern_matcher(*subpatterns)
      PatternObjectDeconstructor.new(self, *subpatterns)
    end
  end

  module AttributeMatcher
    def self.included(klass)
      class << klass
        def pattern_matcher(*subpatterns)
          PatternKeywordArgStyleDeconstructor.new(self, :respond_to?, :__send__, *subpatterns)
        end
      end
    end
  end

  module KeyMatcher
    def self.included(klass)
      class << klass
        def pattern_matcher(*subpatterns)
          PatternKeywordArgStyleDeconstructor.new(self, :has_key?, :[], *subpatterns)
        end
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

    def ancestors
      root? ? [self] : parent.ancestors.unshift(self)
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
      [self, PatternQuantifier.new(0, true)]
    end

    def quantifier?
      raise NotImplementedError
    end

    def quantified?
      (@next and @next.quantifier?) || (root? ? false : @parent.quantified?)
    end

    def root
      root? ? self : @parent.root
    end

    def root?
      @parent == nil
    end

    def validate
      @subpatterns.each(&:validate)
    end

    def match(vals)
      if @next and @next.quantifier?
        q = @next
        repeating_match(vals, q.longest?) do |vs, rest|
          if vs.length < q.min_k
            next false
          end
          vs.all? {|v| yield(v) } and q.match(rest)
        end
      else
        if vals.empty?
          return false
        end
        val, *rest = vals
        yield(val) and (@next ? @next.match(rest) : rest.empty?)
      end
    end

    def append(pattern)
      if @next
        @next.append(pattern)
      else
        if @subpatterns.empty?
          if root?
            new_root = PatternAnd.new(self)
            self.parent = new_root
          end
          pattern.parent = @parent
          @next = pattern
        else
          @subpatterns[-1].append(pattern)
        end
      end
    end

    def inspect
      "#<#{self.class.name}: subpatterns=#{@subpatterns.inspect}>"
    end

    private

    def repeating_match(vals, longest)
      quantifier = @next
      lp = longest_patterns(vals)
      (longest ? lp : lp.reverse).each do |(vs, rest)|
        vars.each {|i| i.set_bind_to(quantifier) }
        begin
          if yield vs, rest
            return true
          end
        rescue PatternNotMatch
        end
        vars.each {|i| i.unset_bind_to(quantifier) }
      end
      false
    end

    def longest_patterns(vals)
      vals.length.downto(0).map do |n|
        [vals.take(n), vals.drop(n)]
      end
    end

    def set_subpatterns_relation
      @subpatterns.each do |i|
        i.parent = self
      end
    end
  end

  class PatternQuantifier < Pattern
    attr_reader :min_k

    def initialize(min_k, longest)
      super()
      @min_k = min_k
      @longest = longest
    end

    def validate
      super
      raise MalformedPatternError unless @prev and ! @prev.quantifier?
      seqs = ancestors.grep(PatternSequence).reverse
      if seqs.any? {|i| i.next and i.next.quantifier? and not i.vars.empty? }
        raise NotImplementedError
      end
      case @parent
      when PatternObjectDeconstructor
        # do nothing
      when PatternSequence
        # do nothing
      else
        raise MalformedPatternError
      end
    end

    def quantifier?
      true
    end

    def match(vals)
      if @next
        @next.match(vals)
      else
        vals.empty?
      end
    end

    def longest?
      @longest
    end

    def inspect
      "#<#{self.class.name}: min_k=#{@min_k}, longest=#{@longest}>"
    end
  end

  class PatternElement < Pattern
    def quantifier?
      false
    end
  end

  class PatternDeconstructor < PatternElement
  end

  class PatternObjectDeconstructor < PatternDeconstructor
    def initialize(deconstructor, *subpatterns)
      super(*subpatterns)
      @deconstructor = deconstructor
    end

    def match(vals)
      super do |val|
        deconstructed_vals = @deconstructor.deconstruct(val)
        if @subpatterns.empty?
          next deconstructed_vals.empty?
        end
        @subpatterns[0].match(deconstructed_vals)
      end
    end

    def inspect
      "#<#{self.class.name}: deconstructor=#{@deconstructor.inspect}, subpatterns=#{@subpatterns.inspect}>"
    end

    private

    def set_subpatterns_relation
      super
      @subpatterns.each_cons(2) do |a, b|
        a.next = b
        b.prev = a
      end
    end
  end

  class PatternKeywordArgStyleDeconstructor < PatternDeconstructor
    def initialize(klass, checker, getter, *keyarg_subpatterns)
      spec = normalize_keyword_arg(keyarg_subpatterns)
      super(*spec.values)
      @klass = klass
      @checker = checker
      @getter = getter
      @spec = spec
    end

    def match(vals)
      super do |val|
        next false unless val.kind_of?(@klass)
        next false unless @spec.keys.all? {|k| val.__send__(@checker, k) }
        @spec.all? do |k, pat|
          pat.match([val.__send__(@getter, k)]) rescue false
        end
      end
    end

    def inspect
      "#<#{self.class.name}: klass=#{@klass.inspect}, spec=#{@spec.inspect}>"
    end

    private

    def normalize_keyword_arg(subpatterns)
      syms = subpatterns.take_while {|i| i.kind_of?(Symbol) }
      rest = subpatterns.drop(syms.length)
      hash = case rest.length
             when 0
               {}
             when 1
               rest[0]
             else
               raise MalformedPatternError
             end
      variables = Hash[syms.map {|i, h| [i, PatternVariable.new(i)] }]
      Hash[variables.merge(hash).map {|k, v| [k, v.kind_of?(Pattern) ? v : PatternValue.new(v)] }]
    end
  end

  class PatternVariable < PatternElement
    attr_reader :name, :val

    def initialize(name)
      super()
      @name = name
      @val = nil
      @bind_to = nil
    end

    def match(vals)
      super do |val|
        bind(val)
        true
      end
    end

    def vars
      [self]
    end

    def set_bind_to(quantifier)
      n = nest_level(quantifier)
      if n == 0
        @val = @bind_to = []
      else
        outer = @val
        (n - 1).times do
          outer = outer[-1]
        end
        @bind_to = []
        outer << @bind_to
      end
    end

    def unset_bind_to(quantifier)
      n = nest_level(quantifier)
      @bind_to = nil
      if n == 0
        # do nothing
      else
        outer = @val
        (n - 1).times do
          outer = outer[-1]
        end
        outer.pop
      end
    end

    def inspect
      "#<#{self.class.name}: name=#{name.inspect}, val=#{@val.inspect}>"
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
      raise PatternMatchError unless quantifier.kind_of?(PatternQuantifier)
      qs = ancestors.map {|i| (i.next and i.next.quantifier?) ? i.next : nil }.find_all {|i| i }.reverse
      qs.index(quantifier) || (raise PatternMatchError)
    end
  end

  class PatternValue < PatternElement
    def initialize(val, compare_by = :===)
      super()
      @val = val
      @compare_by = compare_by
    end

    def match(vals)
      super do |val|
        @val.__send__(@compare_by, val)
      end
    end

    def inspect
      "#<#{self.class.name}: val=#{@val.inspect}>"
    end
  end

  class PatternSequence < PatternElement
    class PatternRewind < PatternElement
      attr_reader :ntimes

      def initialize(ntimes, head_pattern, next_pattern)
        super()
        @ntimes = ntimes
        @head = head_pattern
        @next = next_pattern
      end

      def match(vals)
        if @ntimes > 0
          @ntimes -= 1
          @head.match(vals)
        else
          @next ? @next.match(vals) : vals.empty?
        end
      end

      def inspect
        "#<#{self.class.name}: ntimes=#{@ntimes} head=#{@head.inspect} next=#{@next.inspect}>"
      end
    end

    def match(vals)
      if @next and @next.quantifier?
        repeating_match(vals, @next.longest?) do |rewind|
          if rewind.ntimes < @next.min_k
            next false
          end
          rewind.match(vals)
        end
      else
        with_rewind(make_rewind(1)) do |rewind|
          rewind.match(vals)
        end
      end
    end

    def validate
      super
      if @subpatterns.empty?
        raise MalformedPatternError
      end
      case @parent
      when PatternObjectDeconstructor
        # do nothing
      when PatternSequence
        # do nothing
      else
        raise MalformedPatternError
      end
    end

    private

    def make_rewind(n)
      PatternRewind.new(n, @subpatterns[0], (@next and @next.quantifier?) ? @next.next : @next)
    end

    def repeating_match(vals, longest)
      quantifier = @next
      lp = longest_patterns(vals)
      (longest ? lp : lp.reverse).each do |rewind|
        vars.each {|i| i.set_bind_to(quantifier) }
        begin
          with_rewind(rewind) do |rewind|
            if yield rewind
              return true
            end
          end
        rescue PatternNotMatch
        end
        vars.each {|i| i.unset_bind_to(quantifier) }
      end
      false
    end

    def longest_patterns(vals)
      vals.length.downto(0).map do |n|
        make_rewind(n)
      end
    end

    def with_rewind(rewind)
      @subpatterns[-1].next = rewind
      yield rewind
    ensure
      @subpatterns[-1].next = nil
    end

    def set_subpatterns_relation
      super
      @subpatterns.each_cons(2) do |a, b|
        a.next = b
        b.prev = a
      end
    end
  end

  class PatternAnd < PatternElement
    def match(vals)
      super do |val|
        @subpatterns.all? {|i| i.match([val]) }
      end
    end

    def validate
      super
      raise MalformedPatternError if @subpatterns.empty?
    end
  end

  class PatternOr < PatternElement
    def match(vals)
      super do |val|
        @subpatterns.find do |i|
          begin
            i.match([val])
          rescue PatternNotMatch
            false
          end
        end
      end
    end

    def validate
      super
      raise MalformedPatternError if @subpatterns.empty?
      raise MalformedPatternError unless vars.empty?
    end
  end

  class PatternNot < PatternElement
    def match(vals)
      super do |val|
        begin
          ! @subpatterns[0].match([val])
        rescue PatternNotMatch
          true
        end
      end
    end

    def validate
      super
      raise MalformedPatternError unless @subpatterns.length == 1
      raise MalformedPatternError unless vars.empty?
    end
  end

  class PatternCondition < PatternElement
    def initialize(&condition)
      super()
      @condition = condition
    end

    def match(vals)
      return false unless vals.empty?
      if @condition.call
        @next ? @next.match(vals) : true
      else
        false
      end
    end

    def validate
      super
      raise MalformedPatternError if ancestors.find {|i| i.next and ! i.next.kind_of?(PatternCondition) }
    end

    def inspect
      "#<#{self.class.name}: condition=#{@condition.inspect}>"
    end
  end

  class Env < BasicObject
    def initialize(ctx, val)
      @ctx = ctx
      @val = val
    end

    private

    def with(pat_or_val, guard_proc = nil, &block)
      ctx = @ctx
      pat = pat_or_val.kind_of?(Pattern) ? pat_or_val : PatternValue.new(pat_or_val)
      pat.append(
        PatternCondition.new do
          pat.vars.each_with_object({}) do |v, h|
            if h.has_key?(v.name)
              unless h[v.name] == v.val
                ::Kernel.raise PatternNotMatch
              end
            else
              h[v.name] = v.val
            end
          end
          true
        end
      )
      if guard_proc
        pat.append(PatternCondition.new { with_tmpbinding(ctx, pat.binding, &guard_proc) })
      end
      pat.validate
      if pat.match([@val])
        ret = with_tmpbinding(ctx, pat.binding, &block)
        ::Kernel.throw(:exit_match, ret)
      else
        nil
      end
    rescue PatternNotMatch
    end

    def guard(&block)
      block
    end

    def ___
      PatternQuantifier.new(0, true)
    end

    def ___?
      PatternQuantifier.new(0, false)
    end

    def method_missing(name, *)
      case name.to_s
      when /\A__(\d+)(\??)\z/
        PatternQuantifier.new($1.to_i, ! $2.empty?)
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

          def vars
            []
          end

          private

          def bind(val)
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

    def Seq(*subpatterns)
      PatternSequence.new(*subpatterns)
    end

    def And(*subpatterns)
      PatternAnd.new(*subpatterns)
    end

    def Or(*subpatterns)
      PatternOr.new(*subpatterns)
    end

    def Not(*subpatterns)
      PatternNot.new(*subpatterns)
    end

    class TmpBindingModule < ::Module
    end

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
        raise PatternMatch::NoMatchingPatternError
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

class Hash
  include PatternMatch::KeyMatcher
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
