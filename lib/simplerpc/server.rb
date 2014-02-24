
require 'socket'               # Get sockets from stdlib
require 'simplerpc/socket_protocol'

# rubocop:disable LineLength



module SimpleRPC

  # Thrown when #listen is called but the server
  # is already listening on the port given
  class AlreadyListeningError < Exception
  end

  # SimpleRPC's server.  This wraps an object and exposes its methods to the network.
  #
  # i.e.:
  #
  #   require 'simplerpc/server'
  #
  #   # Expose the Array api on port 27045
  #   s = SimpleRPC::Server.new( ["thing", "thing2"], :port => 27045 )
  #
  #   # Listen in a thread so we can shut down later
  #   Thread.new(){ s.listen }
  #   sleep(10)
  #
  #   # Tell the server to exit cleanly
  #   s.close
  #
  # == Thread Safety
  #
  # The server is thread-safe, and will not interrupt any clients when #close is called
  # (instead it will wait for requests to finish, then shut down).
  #
  # If :threaded is set to true, the server will be able to make many simultaneous calls
  # to the object being proxied.
  #
  # == Controlling a Server
  #
  # The server is thread-safe, and is designed to be run in a thread when blocking on
  # #listen --- calling #close on a listening server will cause the following chain of
  # events:
  #
  # 1. The current client requests will end
  # 2. The socket will close
  # 3. #listen and #close will return (almost) simultaneously
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
  # Setting the :password and :secret options will require authentication to connect.
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
  class Server

    attr_reader :hostname, :port, :obj, :threaded, :timeout
    attr_accessor :verbose_errors, :serialiser, :fast_auth
    attr_writer :password, :secret

    # Create a new server for a given proxy object.
    #
    # The single required parameter, obj, is an object you wish to expose to the
    # network.  This is the API that will respond to RPCs.
    #
    # Takes an option hash with options:
    #
    # [:port] The port on which to listen, or 0 for the OS to set it
    # [:hostname] The hostname of the interface to listen on (omit for all interfaces)
    # [:serialiser] A class supporting #load(IO) and #dump(obj, IO) for serialisation.
    #               Defaults to Marshal.  I recommend using MessagePack if this is not
    #               fast enough.  Note that JSON/YAML do not work as they don't send
    #               terminating characters over the socket.
    # [:verbose_errors] Report all socket errors from clients (by default these will be quashed).
    # [:timeout] Socket timeout in seconds.  Default is infinite (nil)
    # [:threaded] Accept more than one client at once?  Note that proxy object should be thread-safe for this
    #             Default is on.
    # [:password] The password clients need to connect
    # [:secret] The encryption key used during password authentication.  Should be some long random string.
    #           This should be ASCII-8bit encoded (it will be converted if not)
    # [:salt_size] The size of the string used as a nonce during password auth.  Defaults to 10 chars
    # [:fast_auth] Use a slightly faster auth system that is incapable of knowing if it has failed or not.
    #              By default this is off.
    #
    def initialize(obj, opts = {})
      @obj                  = obj
      @port                 = opts[:port].to_i
      @hostname             = opts[:hostname]

      # What format to use.
      @serialiser           = opts[:serialiser] || Marshal

      # Silence errors coming from client connections?
      @verbose_errors       = (opts[:verbose_errors] == true)
      @fast_auth            = (opts[:fast_auth] == true)

      # Should we shut down?
      @close                = false
      @close_in, @close_out = UNIXSocket.pair

      # Connect/receive timeouts
      timeout               = opts[:timeout]

      # Auth
      if opts[:password] && opts[:secret]
        require 'securerandom'
        require 'simplerpc/encryption'
        @password   = opts[:password]
        @secret     = opts[:secret]
        @salt_size  = opts[:salt_size] || 10 # size of salt on key.
      end

      # Threaded or not?
      @threaded             = !(opts[:threaded] == false)
      if @threaded
        @clients            = {}
        @mc                 = Mutex.new # Client list mutex
      end

      # Listener mutex
      @ml                   = Mutex.new
    end

 
    # Set the timeout on all socket operations,
    # including connection
    def timeout=(timeout)
      @timeout      = timeout
      @socket_timeout = nil

      if @timeout.to_f > 0
        secs            = @timeout.floor
        usecs           = (@timeout - secs).floor * 1_000_000
        @socket_timeout = [secs, usecs].pack("l_2")
      end
    end


    # Start listening forever.
    #
    # Use threads and .close to stop the server.
    #
    # Throws AlreadyListeningError when the server is already
    # busy listening for connections
    def listen
      raise 'Server is already listening' unless @ml.try_lock

      # Listen on one interface only if hostname given
      s = create_server_socket

      # Handle clients
      loop do

        # Accept in an interruptable manner
        if (c = interruptable_accept(s))

          # Set timeout directly on socket
          if @socket_timeout
            c.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, @socket_timeout)
            c.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, @socket_timeout)
          end

          # Threaded
          if @threaded

            # Create the id
            id = rand.hash

            # Add to the client list
            @mc.synchronize do
              @clients[id] = Thread.new() do
                # puts "[#{@clients.length+1}->#{id}"
                begin
                  handle_client(c)
                ensure
                  # Remove self from list
                  @mc.synchronize { @clients.delete(id) }
                  # puts "[#{@clients.length}<-#{id}"
                end
              end
              @clients[id].abort_on_exception = true
            end

          # Single-threaded
          else
            # Handle client
            handle_client(c)
          end
        end

        break if @close
      end

      # Wait for threads to end
      @clients.each {|id, thread| thread.join } if @threaded

      # Close socket
      @close = false if @close  # say we've closed
    ensure
      @ml.unlock
    end

    # Return the number of active client threads.
    #
    # Returns 0 if :threaded is set to false.
    def active_client_threads
      # If threaded return a count from the clients list
      return @clients.length if @threaded

      # Else return 0 if not threaded
      return 0
    end

    # Close the server object nicely,
    # waiting on threads if necessary
    def close
      return unless @ml.locked?
      
      # Ask the loop to close
      @close_in.putc 'x' # Tell select to close

      # Wait for loop to end
      while @ml.locked? do
        sleep(1)
      end
    end

  private

    # -------------------------------------------------------------------------
    # Client Management
    #

    # Accept with the ability for other
    # threads to call close
    def interruptable_accept(s)
      c = IO.select([s, @close_out], nil, nil)

      return nil unless c
      if c[0][0] == @close_out
        # @close is set, so consume from socket
        # and return nil
        @close_out.getc
        @close = true
        s.close   # close server socket
        return nil
      end
      return s.accept if !@close && c
      return nil
    rescue IOError
      # cover 'closed stream' errors
      return nil
    end

    # Handle the protocol for client c
    def handle_client(c)
      # Disable Nagle's algorithm
      c.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Encrypted password auth
      if @password && @secret
        begin
          # Send challenge,
          # try secure random data, but fall back to insecure.
          # TODO: also alert the user, or make this fallback optional.
          salt = ''
          begin
            salt = SecureRandom.random_bytes(@salt_size)
          rescue NotImplementedError
            salt = Random.new.bytes(@salt_size)
          end
          SocketProtocol::Simple.send(c, salt)

          # Receive encrypted challenge
          raw = SocketProtocol::Simple.recv(c)

          # D/c if failed
          unless Encryption.decrypt(raw, @secret, salt) == @password
            SocketProtocol::Simple.send(c, SocketProtocol::AUTH_FAIL) unless @fast_auth
            return
          end
          SocketProtocol::Simple.send(c, SocketProtocol::AUTH_SUCCESS) unless @fast_auth
        rescue
          # Auth failure is silent for the server
          return
        end
      end

      # Handle requests
      persist = true
      while !@close && persist do

        # Note, when clients d/c this throws EOFError
        m, args, remote_block_given, persist = SocketProtocol::Stream.recv(c, @serialiser)
        # puts "Method: #{m}, args: #{args}, block?: #{remote_block_given}, persist: #{persist}"

        if m && args

          # Record success status
          result    = nil
          success   = SocketProtocol::REQUEST_SUCCESS

          # Try to make the call, catching exceptions
          begin

            if remote_block_given
              # Proxy with a block that sends back to the client
              result  = @obj.send(m, *args) do |*yield_args|
                SocketProtocol::Stream.send(c, [SocketProtocol::REQUEST_YIELD, yield_args], @serialiser)
                SocketProtocol::Stream.recv(c, @serialiser)
              end

            else
              # Proxy without block for correct exceptions
              result  = @obj.send(m, *args)
            end

          rescue StandardError => se
            result  = se
            success = SocketProtocol::REQUEST_FAIL
          end

          # Send over the result
          # puts "[s] sending result..."
          SocketProtocol::Stream.send(c, [success, result], @serialiser)
        else
          persist = false
        end

      end

    rescue StandardError => e
      case e
      when EOFError
        return
      when Errno::EPIPE, Errno::ECONNRESET,
           Errno::ECONNABORTED, Errno::ETIMEDOUT
        raise e if @verbose_errors
      else
        raise e if @verbose_errors
      end
    ensure
      # Always ensure we close the socket
      c.close
    end

    # -------------------------------------------------------------------------
    # Socket Management
    #

    # Creates a new socket
    # and returns it
    def create_server_socket
      if @hostname
        s = TCPServer.open(@hostname, @port)
      else
        s = TCPServer.open(@port)
      end
      @port = s.addr[1]

      s.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

      return s
    end

  end

end

