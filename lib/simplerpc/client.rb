require 'socket'      # Sockets are in standard library
require 'simplerpc/serialiser'
require 'simplerpc/socket_protocol'

module SimpleRPC 

  # The SimpleRPC client connects to a server, either persistently on on-demand, and makes
  # calls to its proxy object.
  #
  # Once created, you should be able to interact with the client as if it were the remote
  # object.
  #
  class Client

    # Create a new client for the network
    # 
    # hostname:: The hostname of the server
    # port:: The port to connect to
    # serialiser:: An object supporting load/dump for serialising objects.  Defaults to
    #              SimpleRPC::Serialiser
    # timeout:: The socket timeout.  Throws Timeout::TimeoutErrors when exceeded.  Set
    #           to nil to disable.
    def initialize(hostname, port, serialiser=Serialiser.new, timeout=nil)
      @hostname     = hostname
      @port         = port
      @serialiser   = serialiser
      @timeout      = timeout

      @m = Mutex.new
    end

    # Connect to the server,
    # or do nothing if already connected
    def connect
      @m.synchronize{
        _connect
      }
      return connected?
    end

    # Disconnect from the server
    # or do nothing if already disconnected
    def close
      @m.synchronize{
        _disconnect
      }
    end

    # Alias for close
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
      success     = true

      @m.synchronize{
        already_connected = (not (@s == nil))
        _connect if not already_connected
        # send method name and arity
        # #puts "c: METHOD: #{m}. ARITY: #{args.length}"
        _send([m, args.length, already_connected])

        # receive yey/ney
        valid_call = _recv

        #puts "=--> #{valid_call}"

        # call with args
        if valid_call then
          _send( args )
          success, result = _recv
        end
        
        # Then d/c
        _disconnect if not already_connected
      }
     
      # If the call wasn't valid, call super and pretend we don't know about the method
      result = super if not valid_call 

      # If it didn't succeed, treat the payload as an exception
      raise result if not success 
      return result
    end

  private
    # Connect to the server
    def _connect
      @s = TCPSocket.open( @hostname, @port )
      raise "Failed to connect" if not @s
    end

    # Receive data from the server
    def _recv
      @serialiser.load( SocketProtocol::recv(@s, @timeout) )
    end

    # Send data to the server
    def _send(obj)
      SocketProtocol::send(@s, @serialiser.dump(obj), @timeout)
    end

    # Disconnect from the server
    def _disconnect
      return if not @s
      @s.close
      @s = nil
    end
  end

end

