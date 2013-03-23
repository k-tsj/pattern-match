require 'test/unit'
require_relative '../lib/pattern-match'

class TestPatternMatch < Test::Unit::TestCase
  def test_basic
    this = self
    ret = match([0, 1, 2, 3]) do
      with(nil) { flunk }
      with(_[a, 0, 0, b]) { flunk }
      with(_[a, Fixnum , 2, b]) do
        assert_equal(this, self)
        assert_equal(0, a)
        assert_equal(3, b)
        4
      end
      with(_) { flunk }
    end
    assert_equal(4, ret)
    assert_raise(NameError) { a }
    assert_raise(NameError) { b }

    assert_raise(PatternMatch::NoMatchingPatternError) do
      match(0) do
        with(1) { flunk }
        with(2) { flunk }
      end
    end

    match(0) do
      with(i, guard { i.odd? }) { flunk }
      with(i, guard { i.even? }) { pass }
      with(_) { flunk }
    end
  end

  def test_variable_shadowing
    match(0) do
      with(a) do
        assert_equal(0, a)
        match([1, 2]) do
          with(_[a, b]) do
            assert_equal(1, a)
            assert_equal(2, b)
            match([3, 4, 5]) do
              with(_[a, b, c]) do
                assert_equal(3, a)
                assert_equal(4, b)
                assert_equal(5, c)
              end
            end
            assert_equal(1, a)
            assert_equal(2, b)
            assert_raise(NameError) { c }
          end
        end
        assert_equal(0, a)
        assert_raise(NameError) { b }
        assert_raise(NameError) { c }
      end
    end
    assert_raise(NameError) { a }
    assert_raise(NameError) { b }
    assert_raise(NameError) { c }
  end

  def test_lexical_scoping(rec_call = false, f = nil)
    skip 'not supported'
    unless rec_call
      match(0) do
        with(a) do
          assert_equal(0, a)
          test_lexical_scoping(true, ->{ a }) do |g|
            assert_equal(0, a)
            assert_equal(1, g.())
          end
          assert_equal(0, a)
        end
      end
    else
      assert_raise(NameError) { a }
      assert_equal(0, f.())
      match(1) do
        with(a) do
          assert_equal(1, a)
          assert_equal(0, f.())
          yield ->{ a }
          assert_equal(1, a)
          assert_equal(0, f.())
        end
      end
    end
  end

  def test_override_singleton_method
    skip 'Module#prepend not supported' unless Module.private_method_defined?(:prepend)
    match(0) do
      with(_test_override_singleton_method) do
        def self._test_override_singleton_method
          1
        end
        assert_equal(0, _test_override_singleton_method)
      end
    end
  end

  def test_uscore
    match([0, 1, Fixnum]) do
      with(_[_, ! _(Float), _(Fixnum, :==)]) do
        assert_raise(NameError) { _ }
      end
      with(_) { flunk }
    end
  end

  def test_splat
    match([0, 1, 2]) do
      with(_[a, *b]) do
        assert_equal(0, a)
        assert_equal([1, 2], b)
      end
      with(_) { flunk }
    end

    match([0, 1]) do
      with(_[a, *b, c]) do
        assert_equal(0, a)
        assert_equal([], b)
        assert_equal(1, c)
      end
      with(_) { flunk }
    end

    match([0, 1, 2]) do
      with(_[a, *b, c]) do
        assert_equal(0, a)
        assert_equal([1], b)
        assert_equal(2, c)
      end
      with(_) { flunk }
    end

    match([[0], [1], [2]]) do
      with(_[*_[a]]) do
        assert_equal([0, 1, 2], a)
      end
      with(_) { flunk }
    end

    match([0]) do
      with(_[*a, *b]) do
        assert_equal([0], a)
        assert_equal([], b)
      end
    end
  end

  def test_quantifier
    match([0]) do
      with(_[a, _[b, c], ___]) do
        assert_equal(0, a)
        assert_equal([], b)
        assert_equal([], c)
      end
      with(_) { flunk }
    end

    match([0, [1, 2], [3, 4]]) do
      with(_[a, _[b, c], ___]) do
        assert_equal(0, a)
        assert_equal([1, 3], b)
        assert_equal([2, 4], c)
      end
      with(_) { flunk }
    end

    match([0, [1, 2], [3, 4]]) do
      with(_[a, _[b, c], ___, d]) do
        assert_equal(0, a)
        assert_equal([1], b)
        assert_equal([2], c)
        assert_equal([3, 4], d)
      end
      with(_) { flunk }
    end

    match([0, [1, 2], [3, 4]]) do
      with(_[a, _[b, c], __3]) { flunk }
      with(_[a, _[b, c], __2]) do
        assert_equal(0, a)
        assert_equal([1, 3], b)
        assert_equal([2, 4], c)
      end
      with(_) { flunk }
    end

    match([0, [1, 2], [3, 4]]) do
      with(_[a, _[b, ___], ___]) do
        assert_equal(0, a)
        assert_equal([[1, 2], [3, 4]], b)
      end
      with(_) { flunk }
    end

    match([[0, [1, 2], [3, 4]], [5, [6, 7], [8, 9]], [10, [11, 12], [13, 14]]]) do
      with(_[_[a, _[b, ___], ___], ___]) do
        assert_equal([0, 5, 10], a)
        assert_equal([[[1, 2], [3, 4]], [[6, 7], [8, 9]], [[11, 12], [13, 14]]], b)
      end
      with(_) { flunk }
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(___) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[___]) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[_[___]]) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[a, ___, ___]) {}
      end
    end

    match([0]) do
      with(_[a, ___, *b]) do
        assert_equal([0], a)
        assert_equal([], b)
      end
      with(_) { flunk }
    end

    match([0]) do
      with(_[a, ___?, *b]) do
        assert_equal([], a)
        assert_equal([0], b)
      end
      with(_) { flunk }
    end

    match([[0, 1, :a, 'A'], [2, :b, :c, 'B'], ['C'], 3]) do
      with(_[_[a & Fixnum, ___, b & Symbol, ___, c], ___, d]) do
        assert_equal([[0, 1], [2], []], a)
        assert_equal([[:a], [:b, :c], []], b)
        assert_equal(['A', 'B', 'C'], c)
        assert_equal(3, d)
      end
      with(_) { flunk }
    end

    match([0, 1, 2, 4, 5]) do
      with(_[*a, b & Fixnum, __2, *c], guard { b.all?(&:even?) }) do
        assert_equal([0, 1], a)
        assert_equal([2, 4], b)
        assert_equal([5], c)
      end
      with(_) { flunk }
    end

    match([0, 1, 1, 2, 3, 3, 4]) do
      with(_[*a, b, b, *c]) do
        assert_equal([0, 1, 1, 2], a)
        assert_equal(3, b)
        assert_equal([4], c)
      end
      with(_) { flunk }
    end

    match([0, 1, 1, 2, 3, 3, 4]) do
      with(_[*a, b, b, *c], guard { b < 3 }) do
        assert_equal([0], a)
        assert_equal(1, b)
        assert_equal([2, 3, 3, 4], c)
      end
      with(_) { flunk }
    end
  end

  def test_sequence
    match([0, 1]) do
      with(_[Seq(a)]) { flunk }
      with(_[Seq(a, b)]) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end

    match([0, 1]) do
      with(_[Seq(a), Seq(b)]) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end

    match([0, :a, 1, 2, :b, 3]) do
      with(_[Seq(a & Fixnum, b & Symbol, c & Fixnum), ___]) do
        assert_equal([0, 2], a)
        assert_equal([:a, :b], b)
        assert_equal([1, 3], c)
      end
      with(_) { flunk }
    end

    match([0, :a, 1, 2, :b, :c]) do
      with(_[Seq(a & Fixnum, b & Symbol, c & Fixnum), ___]) { flunk }
      with(_) { pass }
    end

    match([0, 1, :a, 2, 3, :b, 4, 5]) do
      with(_[a, Seq(b & Fixnum, c & Symbol, d & Fixnum), ___, e]) do
        assert_equal(0, a)
        assert_equal([1, 3], b)
        assert_equal([:a, :b], c)
        assert_equal([2, 4], d)
        assert_equal(5, e)
      end
      with(_) { flunk }
    end

    match([:a, [[0, 1], [2, 3], [4, 5]], :b]) do
      with(_[a, _[_[Seq(b), ___], ___], ___, c]) do
        assert_equal(:a, a)
        assert_equal([[[0, 1], [2, 3], [4, 5]]], b)
        assert_equal(:b, c)
      end
      with(_) { flunk }
    end

    match([0]) do
      with(_[Seq(a), ___, *b]) do
        assert_equal([0], a)
        assert_equal([], b)
      end
      with(_) { flunk }
    end

    match([0]) do
      with(_[Seq(a), ___?, *b]) do
        assert_equal([], a)
        assert_equal([0], b)
      end
      with(_) { flunk }
    end

    match([0]) do
      with(_[Seq(a), ___, Seq(b), __1]) do
        assert_equal([], a)
        assert_equal([0], b)
      end
      with(_) { flunk }
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(Seq()) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[Seq()]) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match([0]) do
        with(_[a & Seq(0)]) {}
      end
    end

    assert_raise(NotImplementedError) do
      match([0]) do
        with(_[Seq(a & Fixnum, ___), ___]) {}
      end
    end
  end

  def test_and_or_not
    match(1) do
      with(_(0) & _(1)) { flunk }
      with(_) { pass }
    end

    match(1) do
      with(_(0) | _(1)) { pass }
      with(_) { flunk }
    end

    match(1) do
      with(_[] | _(1)) { pass }
      with(_) { flunk }
    end

    match(1) do
      with(! _(0)) { pass }
      with(_) { flunk }
    end

    match(1) do
      with(! _[]) { pass }
      with(_) { flunk }
    end

    match(1) do
      with(a & b) do
        assert_equal(1, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end

    match(1) do
      # You can not just write `with(0 | 1)',
      # because alternation method `|' is an instance method of Pattern.
      with(_ & 0 | 1) { pass }
      with(_) { flunk }
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a | b) {}
      end
    end

    match(1) do
      with(! _(0)) { pass }
      with(_) { flunk }
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(1) do
        with(! a) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a | ___) {}
      end
    end

    assert_raise(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a & ___) {}
      end
    end
  end

  def test_match_without_argument
    assert_equal(1, 2.times.find(&match { with(1) { true }; with(_) { false } }))
  end

  def test_deconstructor_class
    assert_raise(NotImplementedError) do
      c = Class.new
      match(0) do
        with(c.(a)) do
        end
      end
    end
  end

  def test_deconstructor_class_struct
    s = Struct.new(:a, :b, :c)
    match(s[0, 1, 2]) do
      with(s.(a, b, c)) do
        assert_equal(0, a)
        assert_equal(1, b)
        assert_equal(2, c)
      end
      with(_) { flunk }
    end
  end

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

  def test_deconstructor_class_complex
    match(Complex(0, 1)) do
      with(Complex.(a, b)) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end
  end

  def test_deconstructor_class_rational
    match(Rational(0, 1)) do
      with(Rational.(a, b)) do
        assert_equal(0, a)
        assert_equal(1, b)
      end
      with(_) { flunk }
    end
  end

  def test_deconstructor_class_matchdata
    m = /.../.match('abc')
    match(m) do
      with(MatchData.(a)) do
        assert_equal('abc', a)
      end
      with(_) { flunk }
    end

    m = /(.)(.)(.)/.match('abc')
    match(m) do
      with(MatchData.(a, b, c)) do
        assert_equal('a', a)
        assert_equal('b', b)
        assert_equal('c', c)
      end
      with(_) { flunk }
    end
  end

  def test_deconstructor_obj_regexp
    match('abc') do
      with(/./.(a)) { flunk }
      with(a & /.../.(b)) do
        assert_equal('abc', a)
        assert_equal('abc', b)
      end
      with(_) { flunk }
    end

    match('abc') do
      with(a & /(.)(.)(.)/.(b, c ,d)) do
        assert_equal('abc', a)
        assert_equal('a', b)
        assert_equal('b', c)
        assert_equal('c', d)
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
end
