$:.push File.expand_path('../lib', __FILE__)
require 'pattern-match/version'

Gem::Specification.new do |s|
  s.name        = 'pattern-match'
  s.version     = PatternMatch::VERSION
  s.authors     = ['Kazuki Tsujimoto']
  s.email       = ['kazuki@callcc.net']
  s.homepage    = 'https://github.com/k-tsj/pattern-match'
  s.summary     = %q{A pattern matching library}
  s.description = %w{
    A pattern matching library.
  }.join(' ')

  s.files            = `git ls-files`.split("\n")
  s.test_files       = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables      = `git ls-files -- bin/*`.split("\n").map{|f| File.basename(f) }
  s.require_paths    = ['lib']
  s.extra_rdoc_files = ['README.rdoc']
  s.rdoc_options     = ['--main', 'README.rdoc']
end
