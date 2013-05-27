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
        _connected?
      }
    end

    # Call a method that is otherwise clobbered
    # by the client object
    def call(m, *args)
      method_missing(m, *args)
    end

    # Calls RPC on the remote object
    def method_missing(m, *args, &block)
      result      = nil
      success     = true

      @m.synchronize{
        already_connected = _connected?
        _connect if not already_connected
        # send method name and arity
        _send([m, args, already_connected])

        # call with args
        success, result = _recv
        
        # Then d/c
        _disconnect if not already_connected
      }
     
      # If it didn't succeed, treat the payload as an exception
      raise result if not success 
      return result
    end

  private
    # Non-mutexed check for connectedness
    def _connected?
      @s and not @s.closed?
    end

    # Connect to the server
    def _connect
      @s = TCPSocket.open( @hostname, @port )
      raise "Failed to connect" if not _connected?
    end

    # Receive data from the server
    def _recv
      ret = SocketProtocol::recv(@s, @timeout)
      return if not ret
      @serialiser.load( ret )
    end

    # Send data to the server
    def _send(obj)
      SocketProtocol::send(@s, @serialiser.dump(obj), @timeout)
    end

    # Disconnect from the server
    def _disconnect
      return if not _connected?
      @s.close
      @s = nil
    end
  end

end

