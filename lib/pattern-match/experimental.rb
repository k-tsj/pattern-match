require 'pattern-match/core'
require 'continuation'
require 'set'

raise LoadError, 'Module#prepend required' unless Module.respond_to?(:prepend, true)

using PatternMatch if respond_to?(:using, true)

module PatternMatch
  class Pattern
    module Backtrackable
      def match(vals)
        matched = super
        if root? and not matched and not choice_points.empty?
          restore_choice_point
        end
        matched
      end

      def choice_points
        if root?
          @choice_points ||= []
        else
          @parent.choice_points
        end
      end

      private

      def repeating_match(vals, is_greedy)
        super do |vs, rest|
          cont = nil
          if callcc {|c| cont = c; yield vs, rest }
            save_choice_point(cont)
            true
          else
            false
          end
        end
      end

      def save_choice_point(choice_point)
        choice_points.push(choice_point)
      end

      def restore_choice_point
        choice_points.pop.call(false)
      end
    end

    prepend Backtrackable
  end

  module Deconstructable
    remove_method :call
    def call(*subpatterns)
      if Object == self
        PatternKeywordArgStyleDeconstructor.new(Object, :respond_to?, :__send__, *subpatterns)
      else
        pattern_matcher(*subpatterns)
      end
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
      variables = Hash[syms.map {|i| [i, PatternVariable.new(i)] }]
      Hash[variables.merge(hash).map {|k, v| [k, v.kind_of?(Pattern) ? v : PatternValue.new(v)] }]
    end
  end

  class << Set
    def pattern_matcher(*subpatterns)
      PatternSetDeconstructor.new(self, *subpatterns)
    end
  end

  class PatternSetDeconstructor < PatternDeconstructor
    def initialize(klass, *subpatterns)
      super(*subpatterns)
      @klass = klass
    end

    def match(vals)
      super do |val|
        next false unless val.kind_of?(@klass)
        members = val.to_a
        next false unless subpatterns.length <= members.length
        members.permutation(subpatterns.length).find do |perm|
          cont = nil
          if callcc {|c| cont = c; perm.zip(subpatterns).all? {|i, pat| pat.match([i]) } }
            save_choice_point(cont)
            true
          else
            false
          end
        end
      end
    end
  end

  class PatternVariable
    def <<(converter)
      @converter = converter.respond_to?(:call) ? converter : converter.to_proc
      self
    end

    prepend Module.new {
      def initialize(name)
        super
        @converter = nil
      end

      private

      def bind(val)
        super(@converter ? @converter.call(val) : val)
      end
    }
  end
end

class Hash
  include PatternMatch::KeyMatcher
end

class Object
  def assert_pattern(pattern)
    match(self) do
      Kernel.eval("with(#{pattern}) { self }", Kernel.binding)
    end
  end
end
