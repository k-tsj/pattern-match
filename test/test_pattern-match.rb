require 'test/unit'
require_relative '../lib/pattern-match'

class TestPatternMatch < Test::Unit::TestCase
  def test_basic
    this = self
    ret = match([0, 1, 2, 3]) {
      with(nil) { flunk }
      with(_[a, Fixnum , 2, b]) {
        assert_equal(this, self)
        assert_equal(0, a)
        assert_equal(3, b)
        4
      }
      with(_) { flunk }
    }
    assert_equal(4, ret)
    assert_raise(NameError) { a }
    assert_raise(NameError) { b }

    ret = match(0) {
      with(1) { flunk }
      with(2) { flunk }
    }
    assert_nil(ret)

    match(0) {
      with(i, guard { i.odd? }) { flunk }
      with(i, guard { i.even? }) { pass }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[a, a]) {}
      }
    }
  end

  def test_variable_shadowing
    match(0) {
      with(a) {
        assert_equal(0, a)
        match([1, 2]) {
          with(_[a, b]) {
            assert_equal(1, a)
            assert_equal(2, b)
            match([3, 4, 5]) {
              with(_[a, b, c]) {
                assert_equal(3, a)
                assert_equal(4, b)
                assert_equal(5, c)
              }
            }
            assert_equal(1, a)
            assert_equal(2, b)
            assert_raise(NameError) { c }
          }
        }
        assert_equal(0, a)
        assert_raise(NameError) { b }
        assert_raise(NameError) { c }
      }
    }
    assert_raise(NameError) { a }
    assert_raise(NameError) { b }
    assert_raise(NameError) { c }
  end

  def test_uscore
    match([0, 1, Fixnum]) {
      with(_[_, ! _(Float), _(Fixnum, :==)]) {
        assert_raise(NameError) { _ }
      }
      with(_) { flunk }
    }
  end

  def test_splat
    match([0, 1, 2]) {
      with(_[a, *b]) {
        assert_equal(0, a)
        assert_equal([1, 2], b)
      }
      with(_) { flunk }
    }

    match([0, 1]) {
      with(_[a, *b, c]) {
        assert_equal(0, a)
        assert_equal([], b)
        assert_equal(1, c)
      }
      with(_) { flunk }
    }

    match([0, 1, 2]) {
      with(_[a, *b, c]) {
        assert_equal(0, a)
        assert_equal([1], b)
        assert_equal(2, c)
      }
      with(_) { flunk }
    }

    match([[0], [1], [2]]) {
      with(_[*_[a]]) {
        assert_equal([0, 1, 2], a)
      }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[*a, *b]) {}
      }
    }
  end

  def test_quantifier
    match([0]) {
      with(_[a, _[b, c], ___]) {
        assert_equal(0, a)
        assert_equal([], b)
        assert_equal([], c)
      }
      with(_) { flunk }
    }

    match([0, [1, 2], [3, 4]]) {
      with(_[a, _[b, c], ___]) {
        assert_equal(0, a)
        assert_equal([1, 3], b)
        assert_equal([2, 4], c)
      }
      with(_) { flunk }
    }

    match([0, [1, 2], [3, 4]]) {
      with(_[a, _[b, c], ___, d]) {
        assert_equal(0, a)
        assert_equal([1], b)
        assert_equal([2], c)
        assert_equal([3, 4], d)
      }
      with(_) { flunk }
    }

    match([0, [1, 2], [3, 4]]) {
      with(_[a, _[b, c], __3]) { flunk }
      with(_[a, _[b, c], __2]) {
        assert_equal(0, a)
        assert_equal([1, 3], b)
        assert_equal([2, 4], c)
      }
      with(_) { flunk }
    }

    match([0, [1, 2], [3, 4]]) {
      with(_[a, _[b, ___], ___]) {
        assert_equal(0, a)
        assert_equal([[1, 2], [3, 4]], b)
      }
      with(_) { flunk }
    }

    match([[0, [1, 2], [3, 4]], [5, [6, 7], [8, 9]], [10, [11, 12], [13, 14]]]) {
      with(_[_[a, _[b, ___], ___], ___]) {
        assert_equal([0, 5, 10], a)
        assert_equal([[[1, 2], [3, 4]], [[6, 7], [8, 9]], [[11, 12], [13, 14]]], b)
      }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[___]) {}
      }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[_[___]]) {}
      }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[a, ___, ___]) {}
      }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(0) {
        with(_[a, ___, *b]) {}
      }
    }
  end

  def test_and_or_not
    match(1) {
      with(_(0) & _(1)) { flunk }
      with(_) { pass }
    }

    match(1) {
      with(_(0) | _(1)) { pass }
      with(_) { flunk }
    }

    match(1) {
      with(_[] | _(1)) { pass }
      with(_) { flunk }
    }

    match(1) {
      with(! _(0)) { pass }
      with(_) { flunk }
    }

    match(1) {
      with(! _[]) { pass }
      with(_) { flunk }
    }

    match(1) {
      with(a & b) {
        assert_equal(1, a)
        assert_equal(1, b)
      }
      with(_) { flunk }
    }

    match(1) {
      with(_(0) | _(1)) { pass }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(1) {
        with(a | b) {}
      }
    }

    match(1) {
      with(! _(0)) { pass }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(1) {
        with(! a) {}
      }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(1) {
        with(a | ___) {}
      }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(1) {
        with(a & ___) {}
      }
    }
  end

  def test_match_without_argument
    assert_equal(1, 2.times.find(&match { with(1) { true } }))
  end

  def test_extractor_class
    assert_raise(NotImplementedError) {
      c = Class.new
      match(0) {
        with(c.(a)) {
        }
      }
    }
  end

  def test_extractor_class_struct
    s = Struct.new(:a, :b, :c)
    match(s[0, 1, 2]) {
      with(s.(a, b, c)) {
        assert_equal(0, a)
        assert_equal(1, b)
        assert_equal(2, c)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_struct_with_refinements
    skip 'refinements not supported' unless PatternMatch::SUPPORT_REFINEMENTS
    s = Struct.new(:a, :b, :c)
    match(s[0, 1, 2]) {
      with(s[a, b, c]) {
        assert_equal(0, a)
        assert_equal(1, b)
        assert_equal(2, c)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_class_complex
    match(Complex(0, 1)) {
      with(Complex.(a, b)) {
        assert_equal(0, a)
        assert_equal(1, b)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_class_rational
    match(Rational(0, 1)) {
      with(Rational.(a, b)) {
        assert_equal(0, a)
        assert_equal(1, b)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_class_matchdata
    m = /.../.match('abc')
    match(m) {
      with(MatchData.(a)) {
        assert_equal('abc', a)
      }
      with(_) { flunk }
    }

    m = /(.)(.)(.)/.match('abc')
    match(m) {
      with(MatchData.(a, b, c)) {
        assert_equal('a', a)
        assert_equal('b', b)
        assert_equal('c', c)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_obj_regexp
    match('abc') {
      with(/./.(a)) { flunk }
      with(a & /.../.(b)) {
        assert_equal('abc', a)
        assert_equal('abc', b)
      }
      with(_) { flunk }
    }

    match('abc') {
      with(a & /(.)(.)(.)/.(b, c ,d)) {
        assert_equal('abc', a)
        assert_equal('a', b)
        assert_equal('b', c)
        assert_equal('c', d)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_obj_regexp_with_refinements
    skip 'refinements not supported' unless PatternMatch::SUPPORT_REFINEMENTS
    match('abc') {
      with(/./[a]) { flunk }
      with(a & /.../[b]) {
        assert_equal('abc', a)
        assert_equal('abc', b)
      }
      with(_) { flunk }
    }

    match('abc') {
      with(a & /(.)(.)(.)/[b, c ,d]) {
        assert_equal('abc', a)
        assert_equal('a', b)
        assert_equal('b', c)
        assert_equal('c', d)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_obj_proc_with_refinements
    skip 'refinements not supported' unless PatternMatch::SUPPORT_REFINEMENTS
    match(0) {
      with((Proc.new {|i| i + 1 })[a]) {
        assert_equal(1, a)
      }
      with(_) { flunk }
    }
  end

  def test_extractor_obj_symbol_with_refinements
    skip 'refinements not supported' unless PatternMatch::SUPPORT_REFINEMENTS
    match(0) {
      with(:to_s[a]) {
        assert_equal('0', a)
      }
      with(_) { flunk }
    }
  end

  def test_object
    match(10) {
      with(Object.(:to_i => a, :to_s.(16) => b, :no_method => c)) { flunk }
      with(Object.(:to_i => a, :to_s.(16) => b)) {
        assert_equal(10, a)
        assert_equal('a', b)
      }
      with(_) { flunk }
    }

    assert_raise(PatternMatch::MalformedPatternError) {
      match(10) {
        with(Object.(a, b)) {}
      }
    }
  end

  def test_refine_after_requiring_library
    c = Class.new
    ::PatternMatch::NameSpace.module_eval {
      refine c.singleton_class do
        def extract(*)
          [:c]
        end
      end
    }
    match(:c) {
      with(c.(a)) { assert_equal(:c, a) }
      with(_) { flunk }
    }
  end
end
