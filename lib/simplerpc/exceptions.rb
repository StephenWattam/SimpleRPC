



module SimpleRPC

  # Superclass of all RPC-related exceptions
  class RPCError < Exception
   
    attr_reader :cause

    def initialize(exception)
      super(exception)
      @cause = exception
    end

  end


  # Called when the serialiser fails to deserialise something
  class FormatError < RPCError
  end

  # Called when the connection fails
  class ConnectionError < RPCError
  end

  # Thrown when the server raises an exception.
  #
  # The message is set to the server's exception class.
  #
  # FIXME: use #cause in ruby 2.1
  class RemoteException < RPCError
  end

end


