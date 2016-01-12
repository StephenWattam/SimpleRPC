
Gem::Specification.new do |s|
  # About the gem
  s.name        = 'simplerpc'
  s.version     = '0.3.0b'
  s.date        = '2014-04-15'
  s.summary     = 'Simple RPC library'
  s.description = 'A very simple and fast RPC library'
  s.author      = 'Stephen Wattam'
  s.email       = 'stephenwattam@gmail.com'
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

