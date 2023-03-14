require 'rack'
require_relative 'lib/relay_server'
require_relative 'lib/instrumentation'

# A simple health check
map('/ok') { run lambda { |_env| [204, {}, []] } }

# Serve static files
use Rack::Static, urls: ['/'], root: 'public', index: 'index.html'

# Instrument all other requests
use Instrumentation::Middleware

# Serve the websocket
map('/ws') { run RelayServer.new }
