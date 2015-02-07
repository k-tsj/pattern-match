require 'test/unit/assertions'

module Test::Unit::Assertions
  def pass
    assert(true)
  end
end

begin
  if ENV['COVERAGE']
    require 'simplecov'
    SimpleCov.start do
      add_filter '/test/'
    end
  end
rescue LoadError
end
