require 'faye/websocket'

#
# Rack app that handles WebSocket connections for a relay server.
#
# The relay server is responsible for relaying messages between clients
# connected to the same channel. Since the channel is managed in memory, it is
# not possible to have more than one relay server running at the same time. To
# scale the app, you would need to use a shared pub/sub to store the channels.
#
# The request path forms the channel ID.
#
class RelayServer
  KEEPALIVE_TIME = 15 # in seconds

  def initialize
    # Map of channels, keyed by channel ID
    @channels = {}
  end

  def call(env)
    if Faye::WebSocket.websocket?(env)
      initialize_connection(env)
    else
      # Bad request
      [400, {}, ["Not a WebSocket request"]]
    end
  end

private

  def initialize_connection(env)
    websocket = Faye::WebSocket.new(env, nil, { ping: KEEPALIVE_TIME })
    client_id = websocket.object_id

    # Use the request path as the channel ID
    channel_id = env['PATH_INFO'].gsub(%r{^/}, '')

    websocket.on :open do |event|
      log('websocket.open', client_id:, channel_id:)
      add_client(channel_id, websocket)
    end

    websocket.on :message do |event|
      log('websocket.message', client_id:, channel_id:, size_bytes: event.data.size)
      relay_message(channel_id, websocket, event.data)
    end

    websocket.on :close do |event|
      log("websocket.close", client_id:, channel_id:, code: event.code, reason: event.reason)
      remove_client(channel_id, websocket)
      websocket = nil # Allow websocket to be garbage collected
    end

    # Return async Rack response
    websocket.rack_response
  end

  # Add a client to a channel
  def add_client(channel_id, websocket)
    @channels[channel_id] ||= Set.new
    @channels[channel_id] << websocket
  end

  # Relay a message to all clients in a channel except the sender
  def relay_message(channel_id, websocket, message)
    @channels[channel_id].each do |peer|
      next if peer == websocket
      peer.send(message)
    end
  end

  # Remove a client from a channel and close the channel if it's empty
  def remove_client(channel_id, websocket)
    channel = @channels[channel_id]
    return unless channel

    channel.delete(websocket)

    if channel.empty?
      @channels.delete(channel_id)
    end
  end

  # Log a message with key/value attributes
  def log(message, attrs = {})
    attr_list = JSON.generate(attrs) if attrs.any?
    puts "#{message} #{attr_list}"
  end

end
