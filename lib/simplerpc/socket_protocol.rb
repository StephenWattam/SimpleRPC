# Low-level protocol specification for SimpleRPC.
#
# This defines how data is sent at the socket level, primarily controlling what happens with partial sends/timeouts.
module SimpleRPC::SocketProtocol

    # Send already-serialised payload to socket s
    def self.send(s, payload, timeout=nil)
      payload_length = payload.length

      # Send length
      raise Errno::ETIMEDOUT if not IO.select(nil, [s], nil, timeout)
      s.write( payload_length.to_s + "\0" )
      s.flush

      # Alternative way of sending length
      #s.write( [payload_length].pack('N') ) # Pack to 32-bit unsigned int in network byte-order

      # Send rest incrementally
      # puts "[s] send(#{payload})"
      len = 0
      while( len < payload_length and x = IO.select(nil, [s], nil, timeout) )
        len += s.write( payload[len..-1] )
        # puts "[s #{len}/#{payload_length}]"
      end
      s.flush
      raise Errno::ETIMEDOUT if not x
      # puts "[s] sent(#{payload})"
    end

    # Receive raw data from socket s.
    def self.recv(s, timeout=nil)
      # Read the length of the data
      raise Errno::ETIMEDOUT if not IO.select([s], nil, nil, timeout)
      len = s.gets("\0").to_s.to_i
      
      # Alternative way of recving length
      # len = s.read( 4 ).to_s.unpack( 'N' )[0] # Unpack 32-bit unsigned int in network byte order
      return if len == nil or len == 0

      # Then read the rest incrementally
      buf = ""
      while( len > 0 and x = IO.select([s], nil, nil, timeout) )
        # puts "[r (#{buf.length}/#{len})]"
        x = s.read(len)
        len -= x.length
        buf += x
      end
      raise Errno::ETIMEDOUT if not x

      return buf
    end

end
