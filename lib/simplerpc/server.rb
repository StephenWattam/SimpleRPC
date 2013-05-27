

require 'socket'               # Get sockets from stdlib
require 'simplerpc/serialiser'
require 'simplerpc/socket_protocol'

module SimpleRPC 


  # SimpleRPC's server.  This wraps an object and exposes its methods to the network.
  class Server

    attr_reader :hostname, :port, :obj, :threaded
    attr_accessor :silence_errors, :accept_timeout, :timeout, :serialiser
    
    # Create a new server for a given proxy object
    #
    # obj:: The object to proxy the API for---any ruby object
    # port:: The port to listen on
    # hostname:: The ip of the interface to listen on, or nil for all
    # serialiser:: The serialiser to use
    # threaded:: Should the server support multiple clients at once?
    # timeout:: Socket timeout
    def initialize(obj, port=0, hostname=nil, serialiser=Serialiser.new, threaded=false, timeout=nil)
      @obj      = obj 
      @port     = port
      @hostname = hostname

      # What format to use.
      @serialiser = serialiser

      # Silence errors coming from client connections?
      @silence_errors = false   

      # Should we shut down?
      @close  = false

      # Connect/receive timeouts
      @timeout = timeout
      @accept_timeout = 0.2     # How often to check the closing function

      # Threaded or not?
      @threaded = (threaded == true)
      @clients = {} if @threaded
      @m = Mutex.new if @threaded
    end

    # Start listening forever
    def listen
      # Listen on one interface only if hostname given
      if not @s
        if @hostname 
          @s = TCPServer.open( @hostname, @port )
        else
          @s = TCPServer.open( @port )
        end
        @port = @s.addr[1]
        @s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
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

      # Wait for loop to end 
      while(@close)
        sleep(0.1)
      end
    end

  private

    # Accept with the ability for other 
    # threads to call close
    def interruptable_accept(s)
      c = IO.select([s], nil, nil, @accept_timeout)
      
      return s.accept if( not @close and c )
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
          result = nil
          success = true

          # Try to make the call, catching exceptions
          begin
            result = @obj.send(m, *args)
          rescue StandardError => se
            result = se
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
    rescue Exception => e
      case e
      when Errno::EPIPE
        $stderr.puts "Broken Pipe."
        c.close
      when Errno::ECONNRESET 
        $stderr.puts "Connection reset."
        c.close
      when Errno::ECONNABORTED 
        $stderr.puts "Connection aborted."
        c.close
      when Errno::ETIMEDOUT
        $stderr.puts "Connection timeout."
        c.close
      else
        raise e
      end
    end

    # Receive data from a client
    def recv(c)
      ret = SocketProtocol::recv(c, @timeout)
      return if not ret
      result = @serialiser.load( ret )
      return result
    end

    # Send data to a client
    def send(c, obj)
      SocketProtocol::send(c, @serialiser.dump(obj), @timeout)
    end
  end


end

