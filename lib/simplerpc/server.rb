

require 'socket'               # Get sockets from stdlib
require 'simplerpc/serialiser'

module SimpleRPC 

  class Server

    # Create a new server for a given proxy object
    def initialize(proxy, port, hostname=nil, serialiser=Serialiser.new)
      @proxy = proxy
      @port = port
      @hostname = hostname

      # What format to use.
      @serialiser = serialiser

      # Silence errors?
      @silence_errors = true
    end

    # Start listening forever
    def listen
      if @hostname
        @s = TCPServer.open( @hostname, @port )
      else
        @s = TCPServer.open(@port)
      end

      loop{

        begin
          handle_client(@s.accept)
        rescue StandardError => e
          raise e if not @silence_errors
        end
      }
    end

  private
    # Handle the protocol for client c
    def handle_client(c)
      m, arity = recv(c)

      # Check the call is valid for the proxy object
      valid_call = (@proxy.respond_to?(m) and @proxy.method(m).arity == arity)

      send(c, valid_call)

      # Make the call if valid and send the result back
      if valid_call then
        args = recv(c)
        send(c, @proxy.send(m, *args) )
      end

      c.close
    end

    # Send obj to client c
    def send(c, obj)
      payload = @serialiser.serialise( obj )
      c.puts payload.length.to_s
      c.write( payload )
    end

    # Receive data from client c
    def recv(c)
      len = c.gets.chomp.to_i
      buf = ""
      while( len > 0 and x = c.read(len) )
        len -= x.length
        buf += x
      end
      @serialiser.unserialise( x )
    end
  end


end

