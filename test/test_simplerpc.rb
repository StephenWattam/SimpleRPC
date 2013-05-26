require "test/unit"

$:.unshift File.join( File.dirname(__FILE__), "../lib/" )
require 'simplerpc'

class TestSimpleRPC < Test::Unit::TestCase
 
  def test_calls
    assert_equal(@server_object.get_payload.length, @client.length )
    assert_equal(@server_object.get_payload, @client.get_payload)
    assert_equal(@server_object.get_payload, @client.call(:get_payload))
  end

  def test_new_payload
    assert_equal(@new_payload, @client.set_payload(@new_payload))
  end

  def test_serialisation_formats
    # TODO
  end

  def setup
    @server_object = TestObject.new
    @new_payload   = "bndgfuirbfubfduigfdbuifdbudgfidbfguidfbudfgibdfguidfbudgfidbfguidfgbdfugidfbgudfidbfguidfbgdffuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu"

    @server = SimpleRPC::Server.new( @server_object, 27045, nil, SimpleRPC::Serialiser.new, true)
    @client = SimpleRPC::Client.new( '127.0.0.1', 27045, SimpleRPC::Serialiser.new )

    @server_thread = Thread.new(@server){|s| s.listen }
    sleep(0.1)
  end
 
  def teardown
    ## Nothing really
    @server.close
  end
 
end



class TestObject
  def initialize()
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
