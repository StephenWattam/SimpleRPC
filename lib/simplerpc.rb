# SimpleRPC is a very simple RPC library for ruby, designed to be as fast as possible whilst still
# retaining a simple API.
#
# It connects a client to a server which wraps an object, exposing its API over the network socket.
# All data to/from the server is serialised using a serialisation object that is passed to the 
# client/server.
#
# Author:: Stephen Wattam
#

require 'simplerpc/server'
require 'simplerpc/client'
require 'simplerpc/serialiser'

# This module simply contains version information,
# and including it includes all other project files
module SimpleRPC

  VERSION = "0.1.0b"

end
