ENV['BUNDLE_GEMFILE'] = File.expand_path('../Gemfile', __FILE__)
require 'bundler/setup'
require "bundler/gem_tasks"

require "rake/testtask"
task :default => :test
Rake::TestTask.new do |t|
  t.libs << "lib"
  t.test_files = FileList["test/test_*.rb"]
end
