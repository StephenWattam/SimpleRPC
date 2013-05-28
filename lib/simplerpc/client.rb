require 'socket'      # Sockets are in standard library

module SimpleRPC 

  # The SimpleRPC client connects to a server, either persistently on on-demand, and makes
  # calls to its proxy object.
  #
  # Once created, you should be able to interact with the client as if it were the remote
  # object, i.e.:
  #
  #   c = SimpleRPC::Client.new {:hostname => '127.0.0.1', :port => 27045 }
  #   c.length # 2
  #   c.call(:dup) # ["thing", "thing2"]
  #   c.close
  # 
  # == Making Requests
  # 
  # Requests can be made on the client object as if it were local, and these will be
  # proxied to the server.  For methods that are clobbered locally (for example '.class',
  # which will return 'SimpleRPC::Client', you may use #call to send this without local
  # interaction:
  #
  #  c.class         # SimpleRPC::Client
  #  c.call(:class)  # Array
  #
  # The client will throw network errors upon failure, (ERRno::... ), so be sure to catch
  # these in your application.
  #
  # == Modes
  #
  # It is possible to use the client in two modes: _always-on_ and _connect-on-demand_.  
  # The former of these maintains a single socket to the server, and all requests are
  # sent over this.  Call #connect and #disconnect to control this connection.
  #
  # The latter establishes a connection when necessary.  This mode is used whenever the
  # client is not connected, so is a fallback if always-on fails.  There is a small 
  # performance hit to reconnecting each time.
  #
  # == Serialisation Formats
  #
  # By default both client and server use Marshal.  This has proven fast and general,
  # and is capable of sending data directly over sockets.
  #
  # The serialiser also supports MessagePack (the msgpack gem), and this yields a small
  # performance increase at the expense of generality (restrictions on data type).
  #
  # Note that JSON and YAML, though they support reading and writing to sockets, do not 
  # properly terminate their reads and cause the system to hang.  These methods are
  # both slow and limited by comparison anyway, and algorithms needed to support their
  # use require relatively large memory usage.  They may be supported in later versions.
  #
  class Client

    attr_reader :hostname, :port
    attr_accessor :serialiser

    # Create a new client for the network.
    # Takes an options hash, in which :port is required:
    #
    # [:hostname]    The hostname to connect to.  Defaults to localhost
    # [:port]        The port to connect on.  Required.
    # [:serialiser]  A class supporting #dump(object, io) and #load(IO), defaults to Marshal.
    #                I recommend using MessagePack if this is not fast enough
    # [:timeout]     Socket timeout in seconds.
    #
    def initialize(opts = {})
      @hostname     = opts[:hostname]   || '127.0.0.1'
      @port         = opts[:port]
      @serialiser   = opts[:serialiser] || Marshal 
      @timeout      = opts[:timeout]
      raise "Port required" if not @port

      @m = Mutex.new
    end

    # Connect to the server.  
    #
    # Returns true if connected, or false if not.
    #
    # Note that this is only needed if using the client in always-on mode.
    def connect
      @m.synchronize{
        _connect
      }
    end

    # Disconnect from the server.
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
    # by the client object, e.g.:
    #
    #   client.call(:dup) # return a copy of the server object
    #
    def call(m, *args)
      method_missing(m, *args)
    end

    # Calls RPC on the remote object.
    #
    # You should not need to call this directly.
    #
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

    # Set the timeout on the socket.
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

