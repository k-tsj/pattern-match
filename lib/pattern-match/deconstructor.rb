require 'pattern-match/version'

module PatternMatch
  refine Object do
    private

    def pattern_matcher(*subpatterns)
      PatternObjectDeconstructor.new(self, *subpatterns)
    end
  end
end

using PatternMatch if respond_to?(:using, true)

module PatternMatch
  module Deconstructable
    def call(*subpatterns)
      pattern_matcher(*subpatterns)
    end
  end

  refine Class do
    if respond_to?(:import_methods, true)
      import_methods PatternMatch::Deconstructable
    else
      include PatternMatch::Deconstructable
    end

    def deconstruct(val)
      raise NotImplementedError, "need to define `#{__method__}'"
    end

    private

    def accept_self_instance_only(val)
      raise PatternMatch::PatternNotMatch unless val.kind_of?(self)
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

  refine Regexp do
    if respond_to?(:import_methods, true)
      import_methods PatternMatch::Deconstructable
    else
      include PatternMatch::Deconstructable
    end

    def deconstruct(val)
      m = Regexp.new("\\A#{source}\\z", options).match(val.to_s)
      raise PatternMatch::PatternNotMatch unless m
      m.captures.empty? ? [m[0]] : m.captures
    end
  end
end
