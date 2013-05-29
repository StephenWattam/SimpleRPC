require 'socket'      # Sockets are in standard library
require 'simplerpc/socket_protocol'

module SimpleRPC 

  # Exception thrown when the client fails to connect. 
  class AuthenticationError < StandardError
  end

  # Thrown when the server raises an exception.
  #
  # The message is set to the server's exception class.
  class RemoteException < Exception
  end

  # The superclass of a proxy object
  class RemoteObject < BasicObject
  end

  # The SimpleRPC client connects to a server, either persistently on on-demand, and makes
  # calls to its proxy object.
  #
  # Once created, you should be able to interact with the client as if it were the remote
  # object, i.e.:
  #
  #   require 'simplerpc/client'
  #
  #   # Connect
  #   c = SimpleRPC::Client.new(:hostname => '127.0.0.1', :port => 27045)
  #
  #   # Make some calls directly
  #   c.length        # 2
  #   c.call(:dup)    # ["thing", "thing2"]
  #   c.call(:class)  # Array
  #
  #   # Get a proxy object
  #   p = c.get_proxy
  #   c.connect     # always-on mode
  #   p.dup         # ["thing", "thing2"]
  #   p.length      # 2
  #   p.class       # Array
  #
  #   # Disconnect
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
  # === Proxy Objects
  #
  # Calling #get_proxy will return a dynamically-constructed object that lacks any methods
  # other than remote ones---this means it will be almost indistinguishable from a local
  # object:
  #
  #  c.class        # Array
  #  c.dup          # ['thing', 'thing2']
  #
  # This is an exceptionally seamless way of interacting, but you must retain the original
  # client connection in order to call Client#disconnect or use always-on mode.
  #
  # == Exceptions
  #
  # Remote exceptions fired by the server during a call are wrapped in RemoteException.
  #
  # Network errors are exposed directly.  The server will not close a pipe during 
  # an operation, so the most common error is Errno::ECONNREFUSED when the client attempts
  # to reconnect.
  #
  # == Thread Safety
  #
  # Clients are thread-safe and will block when controlling the always-on connection
  # with #connect and #disconnect.
  #
  # If :threaded is true, clients will support multiple connections to the server.  If
  # used in always-on mode, this means it will maintain one re-usable connection, and only
  # spawn new ones if requested.
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
  # == Authentication
  #
  # Setting the :password and :secret options will cause the client to attempt auth
  # on connection.  If this process succeeds, the client will then proceed as before,
  # else the server will forcibly close the socket.  If :fast_auth is on this will cause
  # some kind of random data loading exception from the serialiser.  If :fast_auth is off (default),
  # this will throw a SimpleRPC::AuthenticationError exception.
  #
  # Clients and servers do not tell one another to use auth (such a system would impact
  # speed) so the results of using mismatched configurations are undefined.
  #
  # The auth process is simple and not particularly secure, but is designed to deter casual
  # connections and attacks.  It uses a password that is sent encrypted against a salt sent 
  # by the server to prevent replay attacks.  If you want more reliable security, use an SSH tunnel.
  #
  # The performance impact of auth is small, and takes about the same time as a simple
  # request.  This can be mitigated by using always-on mode.
  #
  class Client

    attr_reader :hostname, :port, :threaded
    attr_accessor :serialiser, :timeout, :fast_auth
    attr_writer :password, :secret

    # Create a new client for the network.
    # Takes an options hash, in which :port is required:
    #
    # [:hostname]    The hostname to connect to.  Defaults to localhost
    # [:port]        The port to connect on.  Required.
    # [:serialiser]  A class supporting #dump(object, io) and #load(IO), defaults to Marshal.
    #                I recommend using MessagePack if this is not fast enough
    # [:timeout]     Socket timeout in seconds.
    # [:password] The password clients need to connect
    # [:secret] The encryption key used during password authentication.  
    #           Should be some long random string that matches the server's.
    # [:fast_auth] Use a slightly faster auth system that is incapable of knowing if it has failed or not.
    #              By default this is off.
    # [:threaded] Support multiple connections to the server (default is off)
    #             If off, threaded requests will queue in the client.
    #
    def initialize(opts = {})

      # Connection details
      @hostname     = opts[:hostname]   || '127.0.0.1'
      @port         = opts[:port]
      raise "Port required" if not @port
      @timeout      = opts[:timeout]

      # Support multiple connections at once?
      @threaded     = (opts[:threaded] == true)

      # Serialiser.
      @serialiser   = opts[:serialiser] || Marshal 

      # Auth system
      if opts[:password] and opts[:secret] then
        require 'simplerpc/encryption'
        @password   = opts[:password]
        @secret     = opts[:secret]
      
        # Check for return from auth?
        @fast_auth  = (opts[:fast_auth] == true)
      end

      # Create a mutex
      @m                     = Mutex.new

      # If threaded is set, we want to avoid blocking on 
      # the mutex acquisition call.  This system allows us to
      # swap out that method call using ruby's first-order stuff.
      @connection_lock       = @m.method((@threaded) ? :try_lock : :lock)
    end

    # Connect to the server.  
    #
    # Returns true if connected, or false if not.
    #
    # Note that this is only needed if using the client in always-on mode.
    def connect
      @m.synchronize{
        @s = _connect
      }
    end

    # Disconnect from the server.
    def close
      @m.synchronize{
        _disconnect(@s)
        @s = nil
      }
    end

    # Alias for close
    alias :disconnect :close

    # Is the client currently connected?
    def connected?
      @m.synchronize{
        _connected?(@s)
      }
    end

    # Call a method that is otherwise clobbered
    # by the client object, e.g.:
    #
    #   client.call(:dup) # return a copy of the server object
    #
    def call(m, *args, &block)
      method_missing(m, *args, &block)
    end

    # Calls RPC on the remote object.
    #
    # You should not need to call this directly.
    #
    def method_missing(m, *args, &block)

      result      = nil
      success     = true

      # See if we can acquire the mutex
      # for the global connection
      if( @connection_lock.call )
        # puts "@s"
        already_connected = _connected?(@s)
        if not already_connected
          raise Errno::ECONNREFUSED, "Failed to connect" if not (@s = _connect)
        end
        # send method name and arity
        _send(@s, [m, args, already_connected])

        # call with args
        success, result = _recv(@s)
        
        # Then d/c
        _disconnect(@s) if not already_connected
      
        # Release mutex
        @m.unlock
      else
        # puts " s"
        # Create new connection
        raise Errno::ECONNREFUSED, "Failed to connect" if not (s = _connect)

        # send method name and arity
        _send(s, [m, args, false])

        # call with args
        success, result = _recv(s)
        
        # Then d/c
        _disconnect(s)
      end

      # puts "[c] #{result}  // #{success}..."
      # If it didn't succeed, treat the payload as an exception
      raise RemoteException.new(result) if not success 
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

    # Returns a proxy object that is all but indistinguishable
    # from the remote object.
    #
    # This allows you to pass the object around whilst retaining control
    # over the rpc client (i.e. calling connect/disconnect).
    #
    # The class returned extends BasicObject and is thus able to pass
    # all calls through to the server.
    #
    def get_proxy
      cls = Class.new(RemoteObject) do
        def initialize(client)
          @client = client
        end

        def method_missing(m, *args, &block)
          @client.call(m, *args)
        end
      end

      return cls.new(self)
    end

  private


    # -------------------------------------------------------------------------
    # Send/Receive
    #

    # Receive data from the server
    def _recv(s)
      SocketProtocol::Stream.recv( s, @serialiser, @timeout )
    end

    # Send data to the server
    def _send(s, obj)
      SocketProtocol::Stream.send( s, obj, @serialiser, @timeout )
    end

    # -------------------------------------------------------------------------
    # Socket management
    #

    # Connect to the server and return a socket
    def _connect
      # Connect to the host
      s = Socket.tcp( @hostname, @port, nil, nil, :connect_timeout => @timeout )
      
      # Disable Nagle's algorithm
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  
      # if auth is required
      if @password and @secret
        salt      = SocketProtocol::Simple.recv( s, @timeout )
        challenge = Encryption.encrypt( @password, @secret, salt ) 
        SocketProtocol::Simple.send( s, challenge, @timeout )
        if not @fast_auth
          if SocketProtocol::Simple.recv( s, @timeout ) != SocketProtocol::AUTH_SUCCESS
            s.close
            raise AuthenticationError, "Authentication failed" 
          end
        end
      end

      # Check and raise
      return s
    end

    # Disconnect a socket from the server 
    def _disconnect(s)
      return if not _connected?(s)

      # Then underlying socket
      s.close if s and not s.closed?
    end

    # Non-mutexed check for connectedness
    def _connected?(s)
      s and not s.closed?
    end

  end

end

