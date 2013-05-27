
module SimpleRPC 

  # This class wraps three possible serialisation systems, providing a common interface to them all.
  #
  # It's not a necessary part of SimpleRPC---you may use any object that supports load/dump---but it is
  # rather handy.
  class Serialiser

    SUPPORTED_METHODS = %w{marshal json msgpack yaml}.map{|s| s.to_sym}

    # Create a new Serialiser with the given method.  Optionally provide a binding to have
    # the serialisation method execute within another context, i.e. for it to pick up
    # on various libraries and classes (though this will impact performance somewhat).
    #
    # Supported methods are:
    #
    # :marshal:: Use ruby's Marshal system.  A good mix of speed and generality.
    # :yaml:: Use YAML.  Very slow but very general
    # :msgpack:: Use MessagePack gem.  Very fast but not very general (limited data format support)
    # :json::  Use JSON.  Also slow, but better for interoperability than YAML.
    #
    def initialize(method = :marshal, binding=nil)
      @method   = method
      @binding  = nil
      raise "Unrecognised serialisation method" if not SUPPORTED_METHODS.include?(method)

      # Require prerequisites and handle msgpack not installed-iness.
      case method
        when :msgpack
          begin 
            gem "msgpack", "~> 0.5"
          rescue Gem::LoadError => e
            $stderr.puts "The :msgpack serialisation method requires the MessagePack gem (msgpack)."
            $stderr.puts "Please install it or use another serialisation method."
            raise e
          end
          require 'msgpack'
          @cls = MessagePack
        when :yaml
          require 'yaml'
          @cls = YAML
        when :json
          require 'json'
          @cls = JSON
        else
          # marshal is alaways available
          @cls = Marshal
      end
    end

    # Serialise to a string
    def dump(obj)
      return eval("#{@cls.to_s}.dump(obj)", @binding) if @binding
      return @cls.send(:dump, obj)
    end

    # Deserialise from a string
    def load(bits)
      return eval("#{@cls.to_s}.load(bits)", @binding) if @binding
      return @cls.send(:load, bits)
    end

    # Return which serlialiser this is using
    def method 
      return @method
    end

  end

end

