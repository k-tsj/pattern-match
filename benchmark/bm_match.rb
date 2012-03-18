require 'pattern-match'

1000.times {
  match([[0, [1, 2], [3, 4]], [5, [6, 7], [8, 9]], [10, [11, 12], [13, 14]]]) {
    with(_[a, _]) { :not_match }
    with(_[a, _]) { :not_match }
    with(_[_[a, _[b, ___], ___], ___]) { }
    with(_[a, _]) { :not_match }
    with(_[a, _]) { :not_match }
  }
}

