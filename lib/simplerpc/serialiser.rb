
require 'yaml'
require 'msgpack'
require 'json'

module SimpleRPC 

  # This class wraps three possible serialisation systems, providing a common interface to them all.
  #
  # It's not a necessary part of SimpleRPC---you may use any object that supports load/dump---but it is
  # rather handy.
  class Serialiser

    # Methods currently supported, and the class they use
    SUPPORTED_METHODS = {:marshal => Marshal,
                         :json    => JSON,
                         :yaml    => YAML,
                         :msgpack => MessagePack}

    # Create a new Serialiser with the given method.  Optionally provide a binding to have
    # the serialisation method execute within another context, i.e. for it to pick up
    # on various libraries and classes.
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
      raise "Unrecognised serialisation method" if not SUPPORTED_METHODS.keys.include?(method)
    end

    # Serialise to a string
    def dump(obj, method=@method)
      return eval("#{SUPPORTED_METHODS[method]}.dump(obj)", @binding) if @binding
      return SUPPORTED_METHODS[method].send(:dump, obj)
    end

    # Deserialise from a string
    def load(bits, method=@method)
      return eval("#{SUPPORTED_METHODS[method]}.load(bits)", @binding) if @binding
      return SUPPORTED_METHODS[method].send(:load, bits)
    end

  end

end

