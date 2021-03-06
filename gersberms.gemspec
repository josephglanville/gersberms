$LOAD_PATH.push File.expand_path('../lib', __FILE__)
require 'gersberms/version'

Gem::Specification.new do |s|
  s.required_rubygems_version = Gem::Requirement.new('> 0') if s.respond_to? :required_rubygems_version=
  s.version = Gersberms::VERSION
  s.name = 'gersberms'
  s.summary = 'Build AMIs with Chef and Berkshelf'
  s.description = 'Gersberms is a simple system for building AWS EC2 AMIs using Chef and Berkshelf'
  s.homepage = 'http://github.com/josephglanville/gersberms'
  s.authors = ['Joseph Glanville']
  s.email = 'jpg@jpg.id.au'
  s.date = '2014-08-15'
  s.default_executable = 'gersberms'
  s.license = 'MIT'
  s.files         = `git ls-files | grep -v -E '(^test|^\.git|client.rb)'`.split
  s.test_files    = `git ls-files | grep ^test`.split
  s.require_paths = ['lib']
  s.executables = ['gersberms']

  s.add_dependency('berkshelf', '~> 3.2')
  s.add_dependency('hashie', '~> 2.0')
  s.add_dependency('aws-sdk', '~> 1.0')
  s.add_dependency('net-ssh', '~> 2.9')
  s.add_dependency('net-scp', '~> 1.2')
  s.add_dependency('rake', '~> 10.4')
  s.add_dependency('thor', '~> 0.19')
end
