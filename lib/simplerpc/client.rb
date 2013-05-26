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
    # serialiser:: An object supporting load/dump for serialising objects.  Defaults to
    #              SimpleRPC::Serialiser
    # timeout:: The socket timeout.  Throws Timeout::TimeoutErrors when exceeded.  Set
    #           to nil to disable.
    def initialize(serialiser=Serialiser.new, timeout=nil, &block)
      raise "A block must be given that returns a subclass of BasicSocket" if not block_given?
      @socket_src   = block
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

      @m.synchronize{
        already_connected = (not (@s == nil))
        _connect if not already_connected
        # send method name and arity
        # #puts "c: METHOD: #{m}. ARITY: #{args.length}"
        _send([m, args.length])

        # receive yey/ney
        valid_call = _recv

        #puts "=--> #{valid_call}"

        # call with args
        if valid_call then
          _send( args )
          result = _recv
        end
        
        # Then d/c
        _disconnect if not already_connected
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
      @s = @socket_src.call()
      raise "Failed to connect" if not @s 
      raise "Socket source didn't return a subclass of BasicSocket" if not @s.is_a? BasicSocket
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

