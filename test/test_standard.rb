require_relative 'helper'
require 'test-unit'
if ENV['DISABLE_REFINEMENTS']
  require 'pattern-match/disable_refinements'
  require 'pattern-match'
else
  require 'pattern-match'
  using PatternMatch
end

class TestStandard < Test::Unit::TestCase
  include TestUtils

  def test_basic
    this = self
    ret = match([0, 1, 2, 3]) do
      with(nil) { flunk }
      with(_[]) { flunk }
      with(_[a, 0, 0, b]) { flunk }
      with(_[a, Integer , 2, b]) do
        assert_equal(this, self)
        assert_equal(0, a)
        assert_equal(3, b)
        4
      end
      with(_) { flunk }
    end
    assert_equal(4, ret)
    assert_raises(NameError) { a }
    assert_raises(NameError) { b }

    assert_raises(PatternMatch::NoMatchingPatternError) do
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

    match([]) do
      with(_[]) { pass }
      with(_) { flunk }
    end

    assert_raises(ArgumentError) do
      match(0) do
        p 1
      end
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
            assert_raises(NameError) { c }
          end
        end
        assert_equal(0, a)
        assert_raises(NameError) { b }
        assert_raises(NameError) { c }
      end
    end
    assert_raises(NameError) { a }
    assert_raises(NameError) { b }
    assert_raises(NameError) { c }
  end

  def test_lexical_scoping(rec_call = false, f = nil)
    omit 'not supported'
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
      assert_raises(NameError) { a }
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
    omit 'Module#prepend is not defined' unless Module.respond_to?(:prepend, true)
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
    match([0, 1, Integer]) do
      with(_[_, ! _(Float), _(Integer, :==)]) do
        assert_raises(NameError) { _ }
      end
      with(_) { flunk }
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_(0, :==, nil)) {}
      end
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

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(___) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[___]) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[_[___]]) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
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
      with(_[_[a & Integer, ___, b & Symbol, ___, c], ___, d]) do
        assert_equal([[0, 1], [2], []], a)
        assert_equal([[:a], [:b, :c], []], b)
        assert_equal(['A', 'B', 'C'], c)
        assert_equal(3, d)
      end
      with(_) { flunk }
    end

    match([0, 1, 2, 4, 5]) do
      with(_[*a, b & Integer, __2, *c], guard { b.all?(&:even?) }) do
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

    match([0, 1]) do
      with(_[a, __0, *_]) do
        assert_equal([0, 1], a)
      end
    end

    match([0, 1]) do
      with(_[a, __0?, *_]) do
        assert_equal([], a)
      end
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
      with(_[Seq(a & Integer, b & Symbol, c & Integer), ___]) do
        assert_equal([0, 2], a)
        assert_equal([:a, :b], b)
        assert_equal([1, 3], c)
      end
      with(_) { flunk }
    end

    match([0, :a, 1, 2, :b, :c]) do
      with(_[Seq(a & Integer, b & Symbol, c & Integer), ___]) { flunk }
      with(_) { pass }
    end

    match([0, 1, :a, 2, 3, :b, 4, 5]) do
      with(_[a, Seq(b & Integer, c & Symbol, d & Integer), ___, e]) do
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

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(Seq()) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(0) do
        with(_[Seq()]) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match([0]) do
        with(_[a & Seq(0)]) {}
      end
    end

    assert_raises(NotImplementedError) do
      match([0]) do
        with(_[Seq(a & Integer, ___), ___]) {}
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

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a | b) {}
      end
    end

    match(1) do
      with(! _(0)) { pass }
      with(_) { flunk }
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(! a) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a | ___) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(a & ___) {}
      end
    end

    match(1) do
      with(And(0, 1)) { flunk }
      with(_) { pass }
    end

    match(1) do
      with(Or(0, 1)) { pass }
      with(_) { flunk }
    end

    match(1) do
      with(Not(0)) { pass }
      with(_) { flunk }
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(And()) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(Or()) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(Not()) {}
      end
    end

    assert_raises(PatternMatch::MalformedPatternError) do
      match(1) do
        with(Not(0, 1)) {}
      end
    end
  end

  def test_match_without_arguments
    assert_equal(1, 2.times.find(&match { with(1) { true }; with(_) { false } }))
  end

  def test_match_too_many_arguments
    assert_raises(ArgumentError) do
      match(0, 1) do
      end
    end
  end

  def test_deconstructor_class
    assert_raises(NotImplementedError) do
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

  def test_refinements
    if ENV['DISABLE_REFINEMENTS']
      assert_kind_of(PatternMatch.const_get(:Pattern), eval_in_unrefined_scope('Class.()'))
      assert_equal(0, eval_in_unrefined_scope('match(0) { with(_) { 0 } }'))
    else
      assert_raises(NoMethodError) do
        eval_in_unrefined_scope('Class.()')
      end
      assert_raises(NoMethodError) do
        eval_in_unrefined_scope('match(0) { with(_) { 0 } }')
      end
    end
  end
end
