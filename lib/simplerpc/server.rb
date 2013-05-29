

require 'socket'               # Get sockets from stdlib
require 'simplerpc/socket_protocol'

module SimpleRPC 


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

    attr_reader :hostname, :port, :obj, :threaded
    attr_accessor :verbose_errors, :serialiser, :timeout, :fast_auth
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
    #             Default is single-threaded mode.
    # [:password] The password clients need to connect
    # [:secret] The encryption key used during password authentication.  Should be some long random string.
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
      @timeout              = opts[:timeout]

      # Auth
      if opts[:password] and opts[:secret] then
        require 'simplerpc/encryption'
        @password   = opts[:password]
        @secret     = opts[:secret]
        @salt_size  = opts[:salt_size] || 10 # size of salt on key.
      end

      # Threaded or not?
      @threaded             = (opts[:threaded] == true)
      if(@threaded)
        @clients            = {}
        @m                  = Mutex.new
      end
    end

    # Start listening forever.
    #
    # Use threads and .close to stop the server.
    #
    def listen
      # Listen on one interface only if hostname given
      create_server_socket if not @s or @s.closed?

      # Handle clients
      loop{

        begin
          # Accept in an interruptable manner
          if( c = interruptable_accept )
            if @threaded
    
              # Create the thread
              id = rand.hash
              thread = Thread.new(id, @m, c){|id, m, c|  
                handle_client(c)

                m.synchronize{
                  @clients.delete(id)
                }
              }

              # Add to the client list
              @m.synchronize{
                @clients[id] = thread
              }
            else
              # Handle client 
              handle_client(c)
            end
          end
        rescue StandardError => e
          raise e if @verbose_errors
        end

        break if @close
      }

      # Wait for threads to end
      if @threaded then
        @clients.each{|id, thread|
          thread.join
        }
      end

      # Close socket
      close_server_sockets

      # Finally, say we've closed
      @close = false if @close
    end

    # Return the number of active clients.
    def active_clients
      @m.synchronize{
        @clients.length
      }
    end

    # Close the server object nicely,
    # waiting on threads if necessary
    def close
      # Ask the loop to close
      @close = true
      @close_in.putc 'x' # Tell select to close

      # Wait for loop to end 
      while(@close)
        sleep(0.1)
      end
    end

  private

    # -------------------------------------------------------------------------
    # Client Management
    #
  
    # Accept with the ability for other 
    # threads to call close
    def interruptable_accept
      c = IO.select([@s, @close_out], nil, nil)
   
      # puts "--> #{c}"

      return nil if not c
      if(c[0][0] == @close_out)  
        # @close is set, so consume from socket
        # and return nil
        @close_out.getc
        return nil 
      end
      return @s.accept if( not @close and c )
    rescue IOError => e
      # cover 'closed stream' errors
      return nil
    end

    # Handle the protocol for client c
    def handle_client(c)
      # Disable Nagle's algorithm
      c.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Encrypted password auth
      if @password and @secret
        # Send challenge
        # XXX: this is notably not crytographically random,
        #      but it's better than nothing against replay attacks
        salt = Random.new.bytes( @salt_size )
        SocketProtocol::Simple.send( c, salt, @timeout )

        # Receive encrypted challenge
        raw = SocketProtocol::Simple.recv( c, @timeout )

        # D/c if failed
        if Encryption.decrypt( raw, @secret, salt) != @password
          SocketProtocol::Simple.send( c, SocketProtocol::AUTH_FAIL, @timeout )   if not @fast_auth
          c.close
          return
        end
        SocketProtocol::Simple.send( c, SocketProtocol::AUTH_SUCCESS, @timeout )     if not @fast_auth
      end

      # Handle requests
      persist = true
      while(not @close and persist) do

        m, args, persist = recv(c)
        # puts "Method: #{m}, args: #{args}, persist: #{persist}"

        if(m and args) then

          # Record success status
          result    = nil
          success   = true

          # Try to make the call, catching exceptions
          begin
            result  = @obj.send(m, *args)
          rescue StandardError => se
            result  = se
            success = false
          end

          # Send over the result
          # puts "[s] sending result..."
          send(c, [success, result] )
        else
          persist = false
        end

      end
        
      # Close
      c.close
    rescue StandardError => e
      case e
      when Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT
        c.close
      else
        raise e 
      end
    end

    # -------------------------------------------------------------------------
    # Send/Receive
    # 

    # Receive data from a client
    def recv(c)
      SocketProtocol::Stream.recv( c, @serialiser, @timeout )
    end

    # Send data to a client
    def send(c, obj)
      SocketProtocol::Stream.send( c, obj, @serialiser, @timeout )
    end

    # -------------------------------------------------------------------------
    # Socket Management
    #

    # Creates a new socket with the given timeout
    def create_server_socket
      if @hostname 
        @s = TCPServer.open( @hostname, @port )
      else
        @s = TCPServer.open( @port )
      end
      @port = @s.addr[1]

      @s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
    end

    # Close the server socket
    def close_server_sockets
      return if not @s 

      # Close underlying socket
      @s.close    if @s and not @s.closed?
      @s = nil
    end


  end


end

