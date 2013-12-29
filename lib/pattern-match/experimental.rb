require 'pattern-match/core'

module PatternMatch
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
end

class Hash
  include PatternMatch::KeyMatcher
end
