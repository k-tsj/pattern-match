require 'pattern-match/core'

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
