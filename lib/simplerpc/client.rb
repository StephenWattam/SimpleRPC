require 'socket'
require 'simplerpc/socket_protocol'

# rubocop:disable LineLength



module SimpleRPC

  # Exception thrown when the client fails to connect.
  class AuthenticationError < StandardError
  end

  # Thrown when the server raises an exception.
  #
  # The message is set to the server's exception class.
  class RemoteException < Exception
    
    attr_reader :remote_exception

    def initialize(exception)
      super(exception)
      @remote_exception = exception
    end

    # Return the backtrace from the original (remote) 
    # exception
    def backtrace
      @remote_exception.backtrace
    end

    # Return a string representing the remote exception
    def to_s
      @remote_exception.to_s
    end
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
  #   c.persist     # always-on mode with 1 connection
  #   p.dup         # ["thing", "thing2"]
  #   p.length      # 2
  #   p.class       # Array
  #   p.each{|x| puts x} # outputs "thing\nthing2\n"
  #
  #   # Disconnect from always-on mode
  #   c.disconnect
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
  # == Blocks
  #
  # Blocks are supported and run on the client-side.  A server object may yield any
  # number of times.  Note that if the client is single-threaded, it is not possible
  # to call further calls when inside the block (if :threading is on this is perfectly
  # acceptable).
  #
  # == Exceptions
  #
  # Remote exceptions fired by the server during a call are wrapped in RemoteException.
  #
  # Network errors are exposed directly.  The server will not close a pipe during
  # an operation, so if using connect-on-demand you should only observe
  # Errno::ECONNREFUSED exceptions.  If using a persistent connection pool,
  # you will encounter either Errno::ECONNREFUSED, Errno::ECONNRESET or EOFError as
  # the serialiser attempts to read from the closed socket.
  #
  # == Thread Safety
  #
  # Clients are thread-safe and will block when controlling the always-on connection
  # with #persist and #close.
  #
  # If :threaded is true, clients will support multiple connections to the server.  If
  # used in always-on mode, this means it will maintain one re-usable connection, and only
  # spawn new ones if requested.
  #
  # == Modes
  #
  # It is possible to use the client in two modes: _always-on_ and _connect-on-demand_,
  # controlled by calling #persist and #disconnect.
  #
  # Always-on mode maintains a pool of connections to the server, and requests
  # are preferentially sent over these (note that if you have threading off, it makes
  # no sense to allocate more than one entry in the pool)
  #
  # connect-on-demand creates a connection when necessary.  This mode is used whenever the
  # client is not connected.  There is a small performance hit to reconnecting each time,
  # especially if you are using authentication.
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

    attr_reader     :hostname,    :port,    :threaded
    attr_accessor   :serialiser,  :timeout, :fast_auth
    attr_writer     :password,    :secret

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
    #           This should be ASCII-8bit encoded (it will be converted if not)
    # [:fast_auth] Use a slightly faster auth system that is incapable of knowing if it has failed or not.
    #              By default this is off.
    # [:threaded] Support multiple connections to the server (default is on)
    #             If off, threaded requests will queue in the client.
    #
    def initialize(opts = {})

      # Connection details
      @hostname     = opts[:hostname]   || '127.0.0.1'
      @port         = opts[:port]
      raise 'Port required' unless @port
      @timeout      = opts[:timeout]

      # Support multiple connections at once?
      @threaded     = !(opts[:threaded] == false)

      # Serialiser.
      @serialiser   = opts[:serialiser] || Marshal

      # Auth system
      if opts[:password] && opts[:secret]
        require 'simplerpc/encryption'
        @password   = opts[:password]
        @secret     = opts[:secret]

        # Check for return from auth?
        @fast_auth  = (opts[:fast_auth] == true)
      end

      # Threading uses @pool, single thread uses @s and @mutex
      if @threaded
        @pool_mutex           = Mutex.new # Controls edits to the pool
        @pool                 = {}        # List of available sockets with
                                          # accompanying mutices
      else
        @mutex                = Mutex.new
        @s                    = nil
      end
    end

    # Connect to the remote server and return two things:
    #
    # * A proxy object for communicating with the server
    # * The client itself, for controlling the connection
    #
    # All options are the same as #new
    #
    def self.new_proxy(opts = {})
      client = self.new(opts)
      proxy = client.get_proxy

      return proxy, client
    end

    # -------------------------------------------------------------------------
    # Persistent connection management
    #

    # Tell the client how many connections to persist.
    #
    # If the client is single-threaded, this can either be 1 or 0.
    # If the client is multi-threaded, it can be any positive integer 
    # value (or 0).
    #
    # #persist(0) is equivalent to #disconnect.
    def persist(pool_size = 1)

      # Check the pool size is positive
      raise 'Invalid pool size requested' if pool_size < 0

      # If not threaded, check pool size is valid and connect/disconnect
      # single socket
      unless @threaded
        raise 'Threading is disabled: pool size must be 1' if pool_size > 1

        # Set socket up
        @mutex.synchronize do
          if pool_size == 0
            _disconnect(@s)
            @s = nil
          else
            @s  = _connect
          end
        end

        return
      end

      # If threaded, create a pool of sockets instead
      @pool_mutex.synchronize do

        # Resize the pool
        if pool_size > @pool.length

          # Allocate more pool space by simply
          # connecting more sockets
          (pool_size - @pool.length).times { @pool[_connect] = Mutex.new }

        else

          # remove from the pool by trying to remove available
          # sockets over and over until they are gone.
          #
          # This has the effect of waiting for clients to be done
          # with the socket, without hanging on any one mutex.
          while @pool.length > pool_size do

            # Go through and remove from the pool if unused.
            @pool.each do |s, m|
              if @pool.length > pool_size && m.try_lock
                _disconnect(s)
                @pool.delete(s)
              end
            end

            # Since we're spinning, delay for a while
            sleep(0.05)
          end
        end
      end
    end

    # Close all persistent connections to the server.
    def disconnect
      persist(0)
    end

    # Is this client maintaining any persistent connections?
    #
    # Returns true/false if the client is single-threaded,
    # or the number of active connections if the client is multi-threaded
    def connected?

      # If not threaded, simply check socket
      @mutex.synchronize { return _connected?(@s) } unless @threaded

      # if threaded, return pool length
      @pool_mutex.synchronize { return (@pool.length) }
    end

    # -------------------------------------------------------------------------
    # Call handling
    #

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
    # You should not need to call this directly (though you are welcome to).
    #
    def method_missing(m, *args, &block)

      # Records the server's return values.
      result      = nil
      success     = true

      # Get a socket preferentially from the pool,
      # and do the actual work
      _get_socket() do |s, persist|

        # send method name and arity
        SocketProtocol::Stream.send(s, [m, args, block_given?, persist], @serialiser, @timeout)

        # Call with args
        success, result = SocketProtocol::Stream.recv(s, @serialiser, @timeout)
        
        # Check if we should yield
        while success == SocketProtocol::REQUEST_YIELD do
          block_result = yield(*result)
          SocketProtocol::Stream.send(s, block_result, @serialiser, @timeout)
          success, result = SocketProtocol::Stream.recv(s, @serialiser, @timeout)
        end

      end

      # If it didn't succeed, treat the payload as an exception
      raise RemoteException.new(result) unless success == SocketProtocol::REQUEST_SUCCESS
      return result
    end

    # Returns a proxy object that is all but indistinguishable
    # from the remote object.
    #
    # This allows you to pass the object around whilst retaining control
    # over the RPC client (i.e. calling persist/disconnect).
    #
    # The class returned extends BasicObject and is thus able to pass
    # all calls through to the server.
    #
    def get_proxy

      # Construct a new class as a subclass of RemoteObject
      cls = Class.new(RemoteObject) do

        # Accept the originating client
        def initialize(client)
          @client = client
        end

        # And handle method_missing by calling the client
        def method_missing(m, *args, &block)
          @client.call(m, *args, &block)
        end
      end

      # Return a new class linked to us
      return cls.new(self)
    end


  # ---------------------------------------------------------------------------
  private

    # -------------------------------------------------------------------------
    # Socket management
    #

    # Connect to the server and return a socket
    def _connect
      # Connect to the host
      s = Socket.tcp(@hostname, @port, nil, nil, connect_timeout: @timeout)

      # Disable Nagle's algorithm
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # if auth is required
      if @password && @secret
        salt      = SocketProtocol::Simple.recv(s, @timeout)
        challenge = Encryption.encrypt(@password, @secret, salt)

        SocketProtocol::Simple.send(s, challenge, @timeout)

        # Check return if not @fast_auth
        unless @fast_auth
          unless SocketProtocol::Simple.recv(s, @timeout) == SocketProtocol::AUTH_SUCCESS
            s.close
            raise AuthenticationError, 'Authentication failed'
          end
        end
      end

      # Check and raise
      return s
    end

    # Get a socket from the reusable pool if possible,
    # else spawn a new one.
    #
    # Blocks if threading is off and the persistent socket
    # is in use.
    def _get_socket

      # If not threaded, try using @s and block on @mutex
      unless @threaded
        # Try to load from pool
        if @s
          # Persistent connection
          @mutex.synchronize do
            
            # Keepalive for pool sockets
            unless _connected?(@s)
              raise Errno::ECONNREFUSED, 'Failed to connect' unless (@s = _connect)
            end

            yield(@s, true) 
          end
        else
          # On-demand connection
          @mutex.synchronize { yield(_connect, false) }
        end
        return
      end

      # If threaded, try using the pool and use try_lock instead,
      # then fall back to using a new connection

      # Look through the pool to find a suitable socket
      @pool.each do |s, m|

        # If not threaded, block.
        if s && m && m.try_lock
          begin

            # Keepalive for pool sockets
            unless _connected?(s)
              raise Errno::ECONNREFUSED, 'Failed to connect' unless (s = _connect)
            end

            # Increase count of active connections and yield
            yield(s, true)
          ensure
            m.unlock
          end
          return
        end
      end

      # Else use a temporary one...
      s = _connect
      yield(s, false)
      _disconnect(s)
    end

    # Disconnect a socket from the server
    def _disconnect(s)
      return unless _connected?(s)

      # Then underlying socket
      s.close if s && !s.closed?
    end

    # Thread-unsafe check for connectedness
    def _connected?(s)
      s && !s.closed?
    end

  end

end
