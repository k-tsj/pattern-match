require 'test/unit'
require_relative '../lib/pattern-match'
require_relative '../lib/pattern-match/experimental'

class TestExperimental < Test::Unit::TestCase
  def test_deconstructor_class_attributes_with_hash
    person_class = Struct.new(:name, :age) do
      include PatternMatch::AttributeMatcher
    end

    company_class = Struct.new(:name) do
      include PatternMatch::AttributeMatcher
    end

    match([person_class.new("Mary", 50), company_class.new("C")]) do
      with(_[company_class.(:name => "Mary"), company_class.(:name => "C")]) { flunk }
      with(_[person_class.(:age, :name => person_name), company_class.(:name => company_name)]) do
        assert_equal("Mary", person_name)
        assert_equal(50, age)
        assert_equal("C", company_name)
      end
      with(_) { flunk }
    end
  end

  def test_deconstructor_class_hash
    match({a: 0, b: 1}) do
      with(Hash.(a: a, b: b, c: c)) { flunk }
      with(Hash.(a: a, b: b)) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end

    match({a: 0, b: 1}) do
      with(Hash.(a: a)) do
        assert_equal(0, a)
      end
      with(_) { flunk }
    end

    match({a: 0}) do
      with(Hash.(a: 0)) { pass }
      with(_) { flunk }
    end

    match({a: 0, b: 1}) do
      with(Hash.(:a, :b, :c)) { flunk }
      with(Hash.(:a, :b)) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end

    match({a: 0, b: 1}) do
      with(Hash.(:a, :b, b: b2)) do
        assert_equal(0, a)
        assert_raise(NameError) { b }
        assert_equal(1, b2)
      end
      with(_) { flunk }
    end
  end

  def test_object
    match(0) do
      with(Object.(:to_s, :to_i => i & 1)) { flunk }
      with(Object.(:to_s, :to_i => i & 0)) do
        assert_equal('0', to_s)
        assert_equal(0, i)
      end
      with(_) { flunk }
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(Object.(a, b)) {}
      end
    end
  end

  def test_object_assert_pattern
    assert_equal([0], [0].assert_pattern('_[Fixnum]'))
    assert_equal([0], [0].assert_pattern('_[a & Fixnum], guard { a.even? }'))
    assert_raise(PatternMatch::NoMatchingPatternError) do
      [0, 1].assert_pattern('_[Fixnum]')
    end
  end
end
