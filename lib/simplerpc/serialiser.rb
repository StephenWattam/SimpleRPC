
require 'yaml'
require 'msgpack'

module SimpleRPC 

  # Serialisation sysetm used for data
  class Serialiser

    # Change to :yaml to use YAML
    def initialize(method = :marshal)
      @method = method
      raise "Unrecognised serialisation method" if not %w{marshal yaml msgpack}.map{|x| x.to_sym }.include?(method)
    end

    # Serialise to a string
    def serialise(obj, method=@method)
      return Marshal.dump(obj)    if method == :marshal
      return YAML.dump(obj)       if method == :yaml
      return obj.to_msgpack
    end

    # Deserialise from a string
    def unserialise(bits, method=@method)
      return Marshal.load(bits)   if method == :marshal
      return YAML.load(bits)      if method == :yaml
      return MessagePack.unpack(bits)
    end

    # Load an object from disk
    def load_file(fn, method=@method)
      return File.open(fn, 'r'){ |f| Marshal.load(f) }      if method == :marshal
      return YAML.load_file(File.read(fn))                  if method == :yaml
      return File.open(fn, 'r'){ |f| MessagePack.unpack( f.read ) } # efficientify me
    end

    # Write an object to disk
    def dump_file(obj, fn, method=@method)
      return File.open(fn, 'w'){ |f| Marshal.dump(obj, f) }   if method == :marshal
      return YAML.dump(obj, File.open(fn, 'w')).close         if method == :yaml
      return File.open(fn, 'w'){ |f| obj.to_msgpack }
    end
  end


end

