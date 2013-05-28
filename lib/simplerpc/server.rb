

require 'socket'               # Get sockets from stdlib
require 'simplerpc/serialiser'

module SimpleRPC 


  # SimpleRPC's server.  This wraps an object and exposes its methods to the network.
  class Server

    attr_reader :hostname, :port, :obj, :threaded
    attr_accessor :silence_errors, :serialiser
    
    # Create a new server for a given proxy object
    #
    # obj:: The object to proxy the API for---any ruby object
    # port:: The port to listen on
    # hostname:: The ip of the interface to listen on, or nil for all
    # serialiser:: The serialiser to use
    # threaded:: Should the server support multiple clients at once?
    # timeout:: Socket timeout
    def initialize(obj, port=0, hostname=nil, serialiser=Serialiser.new, threaded=false, timeout=nil)
      @obj              = obj 
      @port             = port
      @hostname         = hostname

      # What format to use.
      @serialiser       = serialiser

      # Silence errors coming from client connections?
      @silence_errors   = true   

      # Should we shut down?
      @close                = false
      @close_in, @close_out = UNIXSocket.pair

      # Connect/receive timeouts
      @timeout          = timeout

      # Threaded or not?
      @threaded         = (threaded == true)
      @clients          = {} if @threaded
      @m                = Mutex.new if @threaded
    end

    # Start listening forever
    def listen
      # Listen on one interface only if hostname given
      if not @s or @s.closed?
        create_server_socket
      end

      # Handle clients
      loop{

        begin
          # Accept in an interruptable manner
          if( c = interruptable_accept(@s) )
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
          raise e if not @silence_errors
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
      @s.close

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

    # Set the timeout
    def timeout=(timeout)
      @timeout = timeout
      _set_sock_timeout
    end


  private

    # Creates a new socket with the given timeout
    def create_server_socket
      if @hostname 
        @s = TCPServer.open( @hostname, @port )
      else
        @s = TCPServer.open( @port )
      end
      @port = @s.addr[1]

      # Set timeout before accepting
      _set_sock_timeout

      @s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
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

    # Accept with the ability for other 
    # threads to call close
    def interruptable_accept(s)
      c = IO.select([s, @close_out], nil, nil)
    
      return nil if not c
      if(c[0][0] == @close_out)  
        # @close is set, so consume from socket
        # and return nil
        @close_out.getc
        return nil 
      end
      return s.accept if( not @close and c )
    rescue IOError => e
      # cover 'closed stream' errors
      return nil
    end

    # Handle the protocol for client c
    def handle_client(c)
      persist = true

      # Disable Nagle's algorithm
      c.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

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

    # Receive data from a client
    def recv(c)
       @serialiser.load( c )
    end

    # Send data to a client
    def send(c, obj)
      @serialiser.dump( obj, c )
    end
  end


end

