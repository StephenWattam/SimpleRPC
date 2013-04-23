
Gem::Specification.new do |s|
  # About the gem
  s.name        = 'simplerpc'
  s.version     = '0.1.0b'
  s.date        = '2013-04-23'
  s.summary     = 'Simple RPC library'
  s.description = 'A very simple and fast RPC library'
  s.author      = 'Stephen Wattam'
  s.email       = 'stephenwattam@gmail.com'
  s.homepage    = 'http://stephenwattam.com/projects/simplerpc'
  s.required_ruby_version =  ::Gem::Requirement.new(">= 1.9")
  s.license     = 'Beer'
  
  # Files + Resources
  s.files         = Dir.glob("lib/simplerpc/*.rb") + ['LICENSE']
  s.require_paths = ['lib']
  
  # Documentation
  s.has_rdoc         = true 

  # Deps
  # s.add_runtime_dependency 'msgpack',       '~> 0.5'

  # Misc
  s.post_install_message = "Have fun Cing RPs :-)"
end

