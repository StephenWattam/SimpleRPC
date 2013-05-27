require "test/unit"


$:.unshift File.join( File.dirname(__FILE__), "../lib/" )
require 'simplerpc'

class TestSimpleRPC < Test::Unit::TestCase

  PORT = 27045

  # Test on-demand connection (connect-call-disconnect)
  def xtest_on_demand
    config_test(:marshal)
    assert_equal(@server_object.length,               @client.length )
    assert_equal(@server_object.get_payload,          @client.get_payload)
    assert_equal(@server_object.get_payload,          @client.call(:get_payload))
  end

  # Test setting/retrieving data from the wrapped object
  def test_new_payload
    config_test(:marshal)
    new_payload   = "bndgfuirbfubfduigfdbuifdbudgfidbfguidfbudfgibdfguidfbudgfidbfguidfgbdfugidfbgudfidbfguidfbgdffu"
    assert_equal(new_payload,         @client.set_payload(new_payload))
    assert_equal(new_payload.length,  @client.get_payload.length)
    assert_equal(new_payload.length,  @client.length)
    assert_equal(new_payload,         @client.get_payload)

    # and back to the original
    @client.reset_payload
    assert_equal(10,                  @client.length)
  end

  # Test persistent connection (connect-call-call...-disconnect)
  def xtest_persistent_connection
    config_test(:marshal)
    assert_equal(true, @client.connect)

    assert_equal(@server_object.length,               @client.length )
    assert_equal(@server_object.get_payload,          @client.get_payload)
    assert_equal(@server_object.get_payload,          @client.call(:get_payload))

    @client.disconnect
  end

  def xtest_yaml
    # TODO
    config_test(:yaml)


    assert_equal(@server_object.length,               @client.length )
    new_payload   = "bndgfuirbfubfduigfdbuifdbudgfidbfguidfbudfgibdfguidfbudgfidbfguidfgbdfugidfbgudfidbfguidfbgdffuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu"
    assert_equal(new_payload, @client.set_payload(new_payload))
    assert_equal(new_payload.length, @client.get_payload.length)
    assert_equal(new_payload.length, @client.length)
    assert_equal(new_payload, @client.get_payload)

    # and back to the original
    @client.reset_payload
    assert_equal(10, @client.length)

  end

  def xtest_json
    config_test(:json)

    assert_equal(@server_object.length,               @client.length )

    # and back to the original
    @client.reset_payload
    assert_equal(10, @client.length)

  end
  # ---------------------------------------------------------------------------

  def config_test(serialiser, timeout=nil)
    @server.serialiser = SimpleRPC::Serialiser.new(serialiser)
    @server.timeout = timeout

    @client.serialiser = SimpleRPC::Serialiser.new(serialiser)
    @client.timeout = timeout
  end

  def set_server(serv)
    # Close if it's open
    @server.close if @server
    @server_thread.join if @server_thread
    sleep(0.1)  # allow os to catch up with port

    @server = serv

    # Thread for it to listen on
    @server_thread = Thread.new(@server){|s| 
      begin
        s.listen 
      rescue StandardError => e
        $stderr.puts "Error in server thread: #{e.puts} \n\n #{e.backtrace.join("\n")}"
      end
    }
    sleep(0.1)
  end

  def set_client(cl)
    @client.close if @client

    @client = cl
  end

  def setup
    @server_object = TestObject.new

    set_server(SimpleRPC::Server.new( @server_object, PORT, nil)) if not @server
    set_client(SimpleRPC::Client.new( '127.0.0.1', PORT,)) if not @client
  end
 
  def teardown
    ## Nothing really
    @server.close if @server
    @client.close if @client
  end
 
end



class TestObject
  def initialize()
    reset_payload
  end

  def reset_payload
    @payload = {}
    10.times{|x|
      @payload[x] = "#{x}..."
    }
  end

  def get_payload
    @payload
  end

  def set_payload(thing)
    @payload = thing
  end

  def length
    @payload.length
  end

end
