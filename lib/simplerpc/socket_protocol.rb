

module SimpleRPC

  # SocketProtocol defines common low-level aspects of data transfer
  # between client and server.
  #
  # In normal use you can safely ignore this class and simply use Client
  # and Server.
  #
  module SocketProtocol

    # Sent when auth succeeds
    AUTH_SUCCESS = 'C'

    # Sent when auth fails
    AUTH_FAIL    = 'F'

    # Send objects by streaming them through a socket using
    # a serialiser such as Marshal.
    #
    # Fast and with low memory requirements, but is inherently
    # unsafe (arbitrary code execution) and doesn't work with
    # some serialisers.
    #
    # SimpleRPC uses this library for calls, and uses SocketProtocol::Simple
    # for auth challenges (since it is safer)
    #
    module Stream

      # Send using a serialiser writing through the socket
      def self.send(s, obj, serialiser, timeout = nil)
        raise Errno::ETIMEDOUT unless IO.select([], [s], [], timeout)
        return serialiser.dump(obj, s)
      end

      # Recieve using a serialiser reading from the socket
      def self.recv(s, serialiser, timeout = nil)
        raise Errno::ETIMEDOUT unless IO.select([s], [], [], timeout)
        return serialiser.load(s)
      end

    end

    # Sends string buffers back and forth using a simple protocol.
    # 
    # This method is significantly slower, but significantly more secure,
    # than SocketProtocol::Stream, and is used for the auth handshake.
    #
    module Simple

      # Send a buffer
      def self.send(s, buf, timeout = nil)
          # Dump into buffer
          buflen = buf.length

          # Send buffer length
          raise Errno::ETIMEDOUT unless IO.select([], [s], [], timeout)
          s.puts(buflen)

          # Send buffer
          sent = 0
          while sent < buflen && (x = IO.select([], [s], [], timeout)) do
            sent += s.write(buf[sent..-1])
          end
          raise Errno::ETIMEDOUT unless x

      end

      # Receive a buffer
      def self.recv(s, timeout = nil)
          raise Errno::ETIMEDOUT unless IO.select([s], [], [], timeout)
          buflen = s.gets.to_s.chomp.to_i

          return nil if buflen <= 0

          buf = ''
          recieved = 0
          while recieved < buflen && (x = IO.select([s], [], [], timeout)) do
            str = s.read(buflen - recieved)
            buf += str
            recieved += str.length
          end
          raise Errno::ETIMEDOUT unless x

          return buf
      end

    end

  end

end
