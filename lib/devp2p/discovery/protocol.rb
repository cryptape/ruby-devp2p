# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Discovery

    class Protocol < Kademlia::WireInterface

      VERSION = 4

      EXPIRATION = 60 # let messages expire after N seconds

      CMD_ID_MAP = {
        ping: 1,
        pong: 2,
        find_node: 3,
        neighbours: 4
      }.freeze
      REV_CMD_ID_MAP = CMD_ID_MAP.map {|k,v| [v,k] }.to_h.freeze

      # number of required top-level list elements for each cmd_id.
      # elements beyond this length are trimmed.
      CMD_ELEM_COUNT_MAP = {
        ping: 4,
        poing: 3,
        find_node: 2,
        neighbours: 2
      }

      attr :pubkey

      def initialize(app, transport)
        @app = app
        @transport = transport

        @privkey = Utils.decode_hex app.config[:node][:privkey_hex]
        @pubkey = Crypto.privtopub @privkey

        @nodes = {} # nodeid => Node
        @node = Node.new(pubkey, @transport.address)

        @kademlia = KademliaProtocolAdapter.new @node, self

        uri = Utils.host_port_pubkey_to_uri(ip, udp_port, pubkey)
        logger.info "starting discovery proto", enode: uri
      end

      ##
      # return node or create new, update address if supplied
      #
      def get_node(nodeid, address=nil)
        raise ArgumentError, 'invalid nodeid' unless nodeid.size == Kademlia::PUBKEY_SIZE / 8
        raise ArgumentError, 'must give either address or existing nodeid' unless address || @nodes.has_key?(nodeid)

        @nodes[nodeid] = Node.new nodeid, address if !@nodes.has_key?(nodeid)
        node = @nodes[nodeid]

        if address
          raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)
          node.address = address
        end

        node
      end

      def sign(msg)
        msg = Crypto.keccak256 msg
        Crypto.ecdsa_sign msg, @privkey
      end

      ##
      # UDP packets are structured as follows:
      #
      #   hash || signature || packet-type || packet-data
      #
      # * packet-type: single byte < 2**7 // valid values are [1,4]
      # * packet-data: RLP encoded list. Packet properties are serialized in
      #   the order in which they're defined. See packet-data below.
      #
      # Offset |
      # 0      | MDC       | Ensures integrity of packet.
      # 65     | signature | Ensures authenticity of sender, `SIGN(sender-privkey, MDC)`
      # 97     | type      | Single byte in range [1, 4] that determines the structure of Data
      # 98     | data      | RLP encoded, see section Packet Data
      #
      # The packets are signed and authenticated. The sender's Node ID is
      # determined by recovering the public key from the signature.
      #
      #   sender-pubkey = ECRECOVER(Signature)
      #
      # The integrity of the packet can then be verified by computing the
      # expected MDC of the packet as:
      #
      #   MDC = keccak256(sender-pubkey || type || data)
      #
      # As an optimization, implementations may look up the public key by the
      # UDP sending address and compute MDC before recovering the sender ID. If
      # the MDC values do not match, the packet can be dropped.
      #
      def pack(cmd_id, payload)
        raise ArgumentError, 'invalid cmd_id' unless REV_CMD_ID_MAP.has_key?(cmd_id)
        raise ArgumentError, 'payload must be Array' unless payload.is_a?(Array)

        cmd_id = encode_cmd_id cmd_id
        expiration = encode_expiration Time.now.to_i + EXPIRATION

        encoded_data = RLP.encode(payload + [expiration])
        signed_data = Crypto.keccak256 "#{cmd_id}#{encoded_data}"
        signature = Crypto.ecdsa_sign signed_data, @privkey

        raise InvalidSignatureError unless signature.size == 65

        mdc = Crypto.keccak256 "#{signature}#{cmd_id}#{encoded_data}"
        raise InvalidMACError unless mdc.size == 32

        "#{mdc}#{signature}#{cmd_id}#{encoded_data}"
      end

      ##
      # macSize = 256 / 8 = 32
      # sigSize = 520 / 8 = 65
      # headSize = macSize + sigSize = 97
      #
      def unpack(message)
        mdc = message[0,32]
        if mdc != Crypto.keccak256(message[32..-1])
          logger.warn 'packet with wrong mcd'
          raise InvalidMessageMAC
        end

        signature = message[32,65]
        raise InvalidSignatureError unless signature.size == 65

        signed_data = Crypto.keccak256(message[97..-1])
        remote_pubkey = Crypto.ecdsa_recover(signed_data, signature)
        raise InvalidKeyError unless remote_pubkey.size == Kademlia::PUBKEY_SIZE / 8

        cmd_id = decode_cmd_id message[97]
        cmd = REV_CMD_ID_MAP[cmd_id]

        payload = RLP.decode message[98..-1], strict: false
        raise InvalidPayloadError unless payload.instance_of?(Array)

        # ignore excessive list elements as required by EIP-8
        payload = payload[0, CMD_ELEM_COUNT_MAP[cmd]||payload.size]

        return remote_pubkey, cmd_id, payload, mdc
      end

      def receive(address, message)
        logger.debug "<<< message", address: address
        raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)

        begin
          remote_pubkey, cmd_id, payload, mdc = unpack message

          # Note: as of discovery version 4, expiration is the last element for
          # all packets. This might not be the case for a later version, but
          # just popping the last element is good enough for now.
          expiration = decode_expiration payload.pop
          raise PacketExpired if Time.now.to_i > expiration
        rescue DefectiveMessage
          logger.debug $!
          return
        end

        cmd = "recv_#{REV_CMD_ID_MAP[cmd_id]}"
        nodeid = remote_pubkey

        get_node(nodeid, address) unless @nodes.has_key?(nodeid)
        send cmd, nodeid, payload, mdc
      end

      def send_message(node, message)
        raise ArgumentError, 'node must have address' if node.address.nil? || node.address.empty?
        logger.debug ">>> message", address: node.address
        @transport.send_message node.address, message
      end

      def send_ping(node)
        raise ArgumentError, "node must be Node" unless node.is_a?(Node)
        raise ArgumentError, "cannot ping self" if node == @node

        logger.debug ">>> ping", remoteid: node

        version = RLP.sedes.big_endian_int.serialize VERSION
        payload = [
          version,
          Address.new(ip, udp_port, tcp_port).to_endpoint,
          node.address.to_endpoint
        ]

        message = pack CMD_ID_MAP[:ping], payload
        send_message node, message

        message[0,32] # return the MDC to identify pongs
      end

      ##
      # Update ip, port in node table. Addresses can only be learned by ping
      # messages.
      #
      def recv_ping(nodeid, payload, mdc)
        if payload.size != 3
          logger.error "invalid ping payload", payload: payload
          return
        end

        node = get_node nodeid
        logger.debug "<<< ping", node: node

        remote_address = Address.from_endpoint(*payload[1]) # from
        my_address = Address.from_endpoint(*payload[2]) # my address

        get_node(nodeid).address.update remote_address
        @kademlia.recv_ping node, mdc
      end

      def send_pong(node, token)
        logger.debug ">>> pong", remoteid: node

        payload = [node.address.to_endpoint, token]
        raise InvalidPayloadError unless [4,16].include?(payload[0][0].size)

        message = pack CMD_ID_MAP[:pong], payload
        send_message node, message
      end

      def recv_pong(nodeid, payload, mdc)
        if payload.size != 2
          logger.error 'invalid pong payload', payload: payload
          return
        end

        raise InvalidPayloadError unless payload[0].size == 3
        raise InvalidPayloadError unless [4,16].include?(payload[0][0])

        my_address = Address.from_endpoint *payload[0]
        echoed = payload[1]

        if @nodes.include?(nodeid)
          node = get_node nodeid
          @kademlia.recv_pong node, echoed
        else
          logger.debug "<<< unexpected pong from unknown node"
        end
      end

      def send_find_node(node, target_node_id)
        target_node_id = Utils.zpad_int target_node_id, Kademlia::PUBKEY_SIZE/8
        logger.debug ">>> find_node", remoteid: node

        message = pack CMD_ID_MAP[:find_node], [target_node_id]
        send_message node, message
      end

      def recv_find_node(nodeid, payload, mdc)
        node = get_node nodeid

        logger.debug "<<< find_node", remoteid: node
        raise InvalidPayloadError unless payload[0].size == Kademlia::PUBKEY_SIZE/8

        target = Utils.big_endian_to_int payload[0]
        @kademlia.recv_find_node node, target
      end

      def send_neighbours(node, neighbours)
        raise ArgumentError, 'neighbours must be Array' unless neighbours.instance_of?(Array)
        raise ArgumentError, 'neighbours must be Node' unless neighbours.all? {|n| n.is_a?(Node) }

        nodes = neighbours.map {|n| n.address.to_endpoint + [n.pubkey] }
        logger.debug ">>> neighbours", remoteid: node, count: nodes.size

        message = pack CMD_ID_MAP[:neighbours], [nodes]
        send_message node, message
      end

      def recv_neighbours(nodeid, payload, mdc)
        node = get_node nodeid
        raise InvalidPayloadError unless payload.size == 1
        raise InvalidPayloadError unless payload[0].instance_of?(Array)
        logger.debug "<<< neighbours", remoteid: node, count: payload[0].size

        neighbours_set = payload[0].uniq
        logger.warn "received duplicates" if neighbours_set.size < payload[0].size

        neighbours = neighbours_set.map do |n|
          if n.size != 4 || ![4,16].include?(n[0].size)
            logger.error "invalid neighbours format", neighbours: n
            return
          end

          n = n.dup
          nodeid = n.pop
          address = Address.from_endpoint *n
          get_node nodeid, address
        end

        @kademlia.recv_neighbours node, neighbours
      end

      def ip
        @app.config[:discovery][:listen_host]
      end

      def udp_port
        @app.config[:discovery][:listen_port]
      end

      def tcp_port
        @app.config[:p2p][:listen_port]
      end

      private

      def logger
        @logger ||= Logger.new 'p2p.discovery'
      end

      def encode_cmd_id(cmd_id)
        cmd_id.chr
      end

      def decode_cmd_id(byte)
        byte.ord
      end

      def encode_expiration(i)
        RLP::Sedes.big_endian_int.serialize(i)
      end

      def decode_expiration(b)
        RLP::Sedes.big_endian_int.deserialize(b)
      end

    end

  end
end
