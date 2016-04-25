
require File.expand_path("../lib/simplerpc/version", __FILE__)

Gem::Specification.new do |s|
  # About the gem
  s.name        = 'simplerpc'
  s.version     = SimpleRPC::VERSION 
  s.date        = Time.now.to_s.split.first
  s.summary     = 'Simple RPC library'
  s.description = 'A very simple and fast RPC library'
  s.author      = 'Stephen Wattam'
  s.email       = 'steve@stephenwattam.com'
  s.homepage    = 'http://stephenwattam.com/projects/simplerpc'
  s.required_ruby_version =  ::Gem::Requirement.new(">= 2.0")
  s.license     = 'Beerware'
  
  # Files + Resources
  s.files         = Dir.glob("lib/simplerpc/*.rb") + ['./lib/simplerpc.rb', 'LICENSE']
  s.require_paths = ['lib']
  
  # Documentation
  s.has_rdoc         = true 

  # Deps
  # s.add_runtime_dependency 'msgpack',       '~> 0.5'
end

