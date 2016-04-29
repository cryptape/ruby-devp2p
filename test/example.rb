##
# Object with the information to update a decentralized counter.
#
class Token
  include RLP::Sedes::Serializable
  set_serializable_fields(
    counter: RLP::Sedes.big_endian_int,
    sender: RLP::Sedes.binary
  )

  def full_hash
    DEVp2p::Crypto.keccak256 RLP.encode(self)
  end

  def to_s
    "<#{self.class.name}(counter=#{counter} full_hash=#{Utils.encode_hex(full_hash)[0,8]})>"
  rescue
    "<#{self.class.name}>"
  end
end

class ExampleProtocol < DEVp2p::BaseProtocol
  protocol_id 1
  #network_id 0
  max_cmd_id 1

  name 'example'
  version 1

  ##
  # message sending a token and a nonce
  #
  class Token < DEVp2p::Command
    cmd_id 0
    structure(
      token: ::Token
    )
  end

  def initialize(peer, service)
    @config = peer.config
    super(peer, service)
  end

end

class DuplicateFilter
  def initialize(max_items=1024)
    @max_items = max_items
    @filter = []
  end

  def update(data)
    if @filter.include?(data)
      @filter.push @filter.shift
      return false
    else
      @filter.push data
      if @filter.size > @max_items
        @filter.shift
      end
      return true
    end
  end

  def include?(v)
    @filter.include?(v)
  end
end

class ExampleService < DEVp2p::WiredService
  name 'exampleservice'
  default_config(
    example: {
      num_participants: 1
    }
  )

  def initialize(app)
    @config = app.config
    @address = DEVp2p::Crypto.privtopub DEVp2p::Utils.decode_hex(@config[:node][:privkey_hex])

    self.wire_protocol = ExampleProtocol

    super(app)
  end

  def start
    super
  end

  def run
    # do nothing
  end

  def broadcast(obj, origin=nil)
    fmap = {Token: 'token'}
    logger.debug "broadcasting", obj: obj

    exclude_peers = origin ? [origin.peer] : []
    app.services.peermanager.broadcast ExampleProtocol, fmap[obj.class], [obj], {}, nil, exclude_peers
  end

  def on_wire_protocol_stop(proto)
    logger.debug "======================================="
    logger.debug "on_wire_protocol_stop", proto: proto
  end

  def on_wire_protocol_start(proto)
    logger.debug "======================================="
    logger.debug "on_wire_protocol_start", proto: proto, peers: app.services.peermanager.peers

    on_receive_token = ->(proto, token) {
      logger.debug "======================================="
      logger.debug "on_receive token", token: token, proto: proto
      send_token
    }

    proto.receive_token_callbacks.push on_receive_token
    send_token
  end

  def send_token
    sleep rand
    token = Token.new SecureRandom.random_number(1025), @address

    logger.debug "======================================="
    logger.debug "sending token", token: token
    broadcast token
  end

  private

  def logger
    @logger ||= DEVp2p::Logger.new 'Example'
  end

end

class ExampleApp < DEVp2p::BaseApp
  default_config(
    client_version_string: "exampleapp/v0.1/#{RUBY_PLATFORM}/ruby#{RUBY_VERSION}",
    deactivated_services: [],
    post_app_start_callback: nil
  )
end
