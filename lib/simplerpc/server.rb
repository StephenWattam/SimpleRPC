

require 'socket'               # Get sockets from stdlib
require 'simplerpc/serialiser'
require 'simplerpc/socket_protocol'

module SimpleRPC 

  # SimpleRPC's server.  This wraps an object and exposes its methods to the network.
  class Server

    # Create a new server for a given proxy object
    #
    # obj:: The object to proxy the API for---any ruby object
    # port:: The port to listen on
    # hostname:: The ip of the interface to listen on, or nil for all
    # serialiser:: The serialiser to use
    # threaded:: Should the server support multiple clients at once?
    # timeout:: Socket timeout
    def initialize(obj, port, hostname=nil, serialiser=Serialiser.new, threaded=false, timeout=nil)
      @obj      = obj 
      @port     = port
      @hostname = hostname

      # What format to use.
      @serialiser = serialiser

      # Silence errors?
      @silence_errors = true

      # Should we shut down?
      @close  = false

      # Connect/receive timeouts
      @timeout = timeout

      # Threaded or not?
      @threaded = (threaded == true)
      @clients = {} if @threaded
      @m = Mutex.new if @threaded
    end

    # Start listening forever
    def listen
      # Listen on one interface only if hostname given
      if @hostname
        @s = TCPServer.open( @hostname, @port )
      else
        @s = TCPServer.open(@port)
      end

      # Handle clients
      loop{

        begin
          if @threaded
  
            # Create the thread
            id = rand.hash
            thread = Thread.new(id, @m, @s.accept){|id, m, c|  
              handle_client(c)

              # puts "#{id} closing 1"
              m.synchronize{
                @clients.delete(id)
              }
              # puts "#{id} closing 2"
            }

            # Add to the client list
            @m.synchronize{
              @clients[id] = thread
            }
          else
            handle_client(@s.accept)
          end
        rescue StandardError => e
          raise e if not @silence_errors
        end

        break if @close
      }
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

      # Wait on threads
      if @threaded then
        @clients.each{|id, thread|
          thread.join
        }
      end
    end

  private
    # Handle the protocol for client c
    def handle_client(c)
      m, arity = recv(c)

      # Check the call is valid for the proxy object
      valid_call = (@obj.respond_to?(m) and @obj.method(m).arity == arity)

      send(c, valid_call)

      # Make the call if valid and send the result back
      if valid_call then
        args = recv(c)
        send(c, @obj.send(m, *args) )
      end

      c.close
    end

    # Receive data from a client
    def recv(c)
      @serialiser.load( SocketProtocol::recv(c, @timeout) )
    end

    # Send data to a client
    def send(c, obj)
      SocketProtocol::send(c, @serialiser.dump(obj), @timeout)
    end
  end


end

