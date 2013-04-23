require 'socket'      # Sockets are in standard library
require 'simplerpc/serialiser'

# FIXME: TODO: bindings

module SimpleRPC 

  class Client
    def initialize(hostname, port, serialiser=Serialiser.new)
      @hostname     = hostname
      @port         = port
      @serialiser   = serialiser

      @m = Mutex.new
    end

    def connect
      @m.synchronize{
        _connect
      }
    end

    def close
      @m.synchronize{
        _disconnect
      }
    end
    alias :disconnect :close

    # Is the client currently connected?
    def connected?
      @m.synchronize{
        not @s == nil
      }
    end

    # Call a method that is otherwise clobbered
    # by the client object
    def call(m, *args)
      method_missing(m, *args)
    end

    # Calls RPC on the remote object
    def method_missing(m, *args, &block)
      valid_call  = false
      result      = nil

      @m.synchronize{
        _connect
        # send method name and arity
        # puts "c: METHOD: #{m}. ARITY: #{args.length}"
        _send([m, args.length])

        # receive yey/ney
        valid_call = _recv

        # call with args
        if valid_call then
          _send( args )
          result = _recv
        end
        
        # Then d/c
        _disconnect 
      }
     
      # If the call wasn't valid, call super
      if not valid_call then
        result = super
      end

      return result
    end

  private
    # Connect to the server
    def _connect
      return if @s
      @s = TCPSocket.open( @hostname, @port)
    end

    # Send to the server
    def _send(obj)
      raise "Not connected" if not @s
      payload = @serialiser.serialise( obj ) 
      @s.puts payload.length.to_s
      # puts "#{payload} // #{@s.write( payload )}"
      @s.write( payload )
    end

    # Receive from the server
    def _recv
      raise "Not connected" if not @s
      len = @s.gets.chomp.to_i

      buf = ""
      while( len > 0 and x = @s.read(len) )
        len -= x.length
        buf += x
      end
      @serialiser.unserialise( buf )
    end

    # Disconnect from the server
    def _disconnect
      return if not @s
      @s.close
      @s = nil
    end
  end

end

