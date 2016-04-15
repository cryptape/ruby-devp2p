# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # DEV P2P Wire Protocol
  #
  # @see https://github.com/ethereum/wiki/wiki/%C3%90%CE%9EVp2p-Wire-Protocol
  #
  class P2PProtocol < BaseProtocol

    class Ping < Command
      cmd_id 2

      def receive(proto, data)
        proto.send_pong
      end
    end

    class Pong < Command
      cmd_id 3
    end

    class Hello < Command
      cmd_id 0
      decode_strict false # don't throw for additional list elements as mandated by EIP-8

      structure([
        ['version', RLP::Sedes.big_endian_int],
        ['client_version_string', RLP::Sedes.binary],
        ['capabilities', RLP::Sedes::CountableList.new(
          RLP::Sedes::List.new(elements: [RLP::Sedes.binary, RLP::Sedes.big_endian_int])
        )],
        ['listen_port', RLP::Sedes.big_endian_int],
        ['remote_pubkey', RLP::Sedes.binary]
      ])

      def create(proto)
        { version: proto.version,
          client_version_string: proto.config['client_version_string'],
          capabilities: proto.peer.capabilities,
          listen_port: proto.config['p2p']['listen_port'],
          remote_pubkey: proto.config['node']['id'] }
      end

      def receive(proto, data)
        logger.debug 'receive_hello', peer: proto.peer, version: data['version']

        reasons = proto.class::Disconnect::Reason
        if data['remote_pubkey'] == proto.config['node']['id']
          logger.debug 'connected myself'
          return proto.send_disconnect(reason: reasons[:connected_to_self])
        end

        proto.peer.receive_hello proto, data
        super(proto, data)
      end

      private

      def logger
        @logger = Logger.new 'p2p.protocol'
      end

    end

    class Disconnect < Command
      cmd_id 1

      structure [['reason', RLP::Sedes.big_endian_int]]

      Reason = {
        disconnect_requested: 0,
        tcp_sub_system_error: 1,
        bad_protocol: 2, # e.g. a malformed message, bad RLP, incorrect magic number
        useless_peer: 3,
        too_many_peers: 4,
        already_connected: 5,
        incompatible_p2p_version: 6,
        null_node_identity_received: 7,
        client_quitting: 8,
        unexpected_identity: 9,
        connected_to_self: 10,
        timeout: 11,
        subprotocol_error: 12,
        other: 16
      }.freeze

      def reason_key(id)
        Reason.invert[id]
      end

      def reason_name(id)
        key = reason_key id
        key ? key.to_s : "unknown (id:#{id})"
      end

      def create(proto, reason=Reason[:client_quitting])
        raise ArgumentError, "unknown reason" unless reason_key(reason)
        logger.debug "send_disconnect", peer: proto.peer, reason: reason_name(reason)

        proto.peer.report_error "sending disconnect #{reason_name(reason)}"

        after(0.5) { proto.peer.stop }

        {reason: reason}
      end

      def receive(proto, data)
        logger.debug "receive_disconnect", peer: proto.peer, reason: reason_name(data['reason'])
        proto.peer.report_error "disconnected #{reason_name[data['reason']]}"
        proto.peer.stop
      end
    end

    class <<self
      # special: we need this packet before the protocol can be initialized
      def get_hello_packet(peer)
        res = {
          version: 55,
          client_version_string: peer.config['client_version_string'],
          capabilities: peer.capabilities,
          listen_port: peer.config['p2p']['listen_port'],
          remote_pubkey: peer.config['node']['id']
        }

        payload = Hello.encode_payload(res)
        Packet.new protocol_id, Hello.cmd_id, payload
      end
    end

    name 'p2p'
    protocol_id 0
    version 4
    max_cmd_id 15
    commands [Ping, Pong, Hello, Disconnect]

    attr :config

    def initialize(peer, service)
      raise ArgumentError, "invalid peer" unless peer.respond_to?(:capabilities)
      raise ArgumentError, "invalid peer" unless peer.respond_to?(:stop)
      raise ArgumentError, "invalid peer" unless peer.respond_to?(:receive_hello)

      @config = peer.config
      super(peer, service)

      @monitor = ConnectionMonitor.new self
    end

    def stop
      @monitor.stop
      super
    end

    private

    def logger
      @logger = Logger.new 'p2p.protocol'
    end

  end

end
