# Low-level protocol specification for SimpleRPC.
#
# This defines how data is sent at the socket level, primarily controlling what happens with partial sends/timeouts.
module SimpleRPC::SocketProtocol
  
    # Send already-serialised payload to socket s
    def self.send(s, payload, timeout=nil)
      # Send length
      raise Timeout::TimeoutError if not IO.select(nil, [s], nil, timeout)
      s.puts(payload.length.to_s)

      # Send rest incrementally
      #puts "[s] send(#{payload})"
      len = payload.length
      while( len > 0 and x = IO.select(nil, [s], nil, timeout) )
        len -= s.write( payload )
      end
      raise Timeout::TimeoutError if not x
      #puts "[s] sent(#{payload})"
    end

    # Receive raw data from socket s.
    def self.recv(s, timeout=nil)
      # Read the length of the data
      raise Timeout::TimeoutError if not IO.select([s], nil, nil, timeout)
      len = s.gets.chomp.to_i

      # Then read the rest incrementally
      buf = ""
      while( len > 0 and x = IO.select([s], nil, nil, timeout) )
        #puts "[s (#{len})]"
        x = s.read(len)
        len -= x.length
        buf += x
      end
      raise Timeout::TimeoutError if not x

      return buf
      #puts "[s] recv(#{buf})"
    end

end
