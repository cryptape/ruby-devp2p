# -*- encoding : ascii-8bit -*-
module DEVp2p

  ##
  # A service which has an associated WireProtocol.
  #
  # peermanager checks all services registered with app.services
  #   if service is instance of WiredService
  #     add WiredService.wire_protocol to announced capabilities
  #     if a peer with the same protocol is connected
  #       a WiredService.wire_protocol instance is created
  #         with instances of Peer and WiredService
  #       WiredService.wire_protocol(Peer.new, WiredService.new)
  #
  class WiredService < BaseService
    name 'wired'

    attr_accessor :wire_protocol

    def on_wire_protocol_start(proto)
      raise ArgumentError, "argument is not a protocol" unless proto.is_a?(BaseProtocol)
    end

    def on_wire_protocol_stop(proto)
      raise ArgumentError, "argument is not a protocol" unless proto.is_a?(BaseProtocol)
    end

  end

end
