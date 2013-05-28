require 'socket'      # Sockets are in standard library
require 'simplerpc/serialiser'

module SimpleRPC 

  # The SimpleRPC client connects to a server, either persistently on on-demand, and makes
  # calls to its proxy object.
  #
  # Once created, you should be able to interact with the client as if it were the remote
  # object.
  #
  class Client

    attr_reader :hostname, :port
    attr_accessor :serialiser

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

      # puts "[c] calling #{m}..."
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
     
      # puts "[c] /calling #{m}..."
      # If it didn't succeed, treat the payload as an exception
      raise result if not success 
      return result

    # rescue StandardError => e
    #   $stderr.puts "-> #{e}, #{e.backtrace.join("--")}"
    #   case e
    #   when Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT
    #     c.close
    #   else
    #     raise e
    #   end
    end

    # Set the timeout
    def timeout=(timeout)
      @m.synchronize{
        @timeout = timeout
        _set_sock_timeout
      }
    end

  private
    # Non-mutexed check for connectedness
    def _connected?
      @s and not @s.closed?
    end

    # Applies the timeout to the socket
    def _set_sock_timeout
      # Set timeout on socket
      if @timeout and @s
        usecs = (@timeout - @timeout.to_i) * 1_000_000
        optval = [@timeout.to_i, usecs].pack("l_2")
        @s.setsockopt Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval
        @s.setsockopt Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval
      end
    end

    # Connect to the server
    def _connect
      # Thanks to http://www.mikeperham.com/2009/03/15/socket-timeouts-in-ruby/
      # Look up hostname and construct socket
      addr = Socket.getaddrinfo( @hostname, nil )
      @s   = Socket.new( Socket.const_get(addr[0][0]), Socket::SOCK_STREAM, 0 )
 
      # Set timeout *before* connecting
      _set_sock_timeout

      # Connect
      @s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      @s.connect(Socket.pack_sockaddr_in(port, addr[0][3]))
     
      # Check and raise
      return _connected?
    end

    # Receive data from the server
    def _recv
      @serialiser.load( @s )
    end

    # Send data to the server
    def _send(obj)
      @serialiser.dump( obj, @s )
    end

    # Disconnect from the server
    def _disconnect
      return if not _connected?
      @s.close
      @s = nil
    end
  end

end

