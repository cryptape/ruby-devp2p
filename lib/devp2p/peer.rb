# -*- encoding : ascii-8bit -*-

module DEVp2p

  class Peer
    include Celluloid

    DUMB_REMOTE_TIMEOUT = 10.0

    attr :config, :safe_to_read

    def initialize(peermanager, socket, remote_pubkey=nil)
      @peermanager = peermanager
      @socket = socket
      @config = peermanager.config

      @protocols = {}

      @stopped = false
      @hello_received = false

      @remote_client_version = ''
      logger.debug "peer init", peer: self

      privkey = Utils.decode_hex @config[:node][:privkey_hex]
      hello_packet = P2PProtocol.get_hello_packet self

      @mux = MultiplexedSession.new privkey, hello_packet, remote_pubkey
      @remote_pubkey = remote_pubkey

      connect_service @peermanager

      # assure, we don't get messages while replies are not read
      @safe_to_read = Celluloid::Condition.new
      safe_to_read.broadcast

      # stop peer if hello not received in DUMB_REMOTE_TIMEOUT
      after(DUMB_REMOTE_TIMEOUT) { check_if_dumb_remote }
    end

    ##
    # if peer is responder, then the remote_pubkey will not be available before
    # the first packet is received
    #
    def remote_pubkey
      @mux.remote_pubkey
    end

    def remote_pubkey=(key)
      @remote_pubkey_available = !!key
      @mux.remote_pubkey = key
    end

    def to_s
      pn = ip_port.join(':')
      cv = @remote_client_version.split('/')[0,2].join('/')
      "<Peer #{pn} #{cv}>"
    end

    def report_error(reason)
      pn = ip_port.join(':') || 'ip:port not available'
      @peermanager.errors.add pn, reason, @remote_client_version
    end

    def ip_port
      _, port, _, ip = @socket.peeraddr
      return ip, port
    rescue
      logger.debug "ip_port failed: #{e}"
      raise e
    end

    def connect_service(service)
      raise ArgumentError, "service must be WiredService" unless service.is_a?(WiredService)

      # create protocol instance which connects peer with service
      protocol_class = service.wire_protocol
      protocol = protocol_class.new self, service

      # register protocol
      raise PeerError, 'protocol already connected' if @protocols.has_key?(protocol_class)
      logger.debug "registering protocol", protocol: protocol.name, peer: self

      @protocols[protocol_class] = protocol
      @mux.add_protocol protocol.protocol_id

      protocol.start
    end

    def has_protocol?(protocol)
      @protocols.has_key?(protocol)
    end

    def receive_hello(proto, version, client_version_string, capabilities, listen_port, remote_pubkey)
      logger.info 'received hello', version: version, client_version: client_version_string, capabilities: capabilities

      raise ArgumentError, "invalid remote pubkey" unless remote_pubkey.size == 64
      raise ArgumentError, "remote pubkey mismatch" if @remote_pubkey_available && @remote_pubkey != remote_pubkey

      @hello_received = true

      # enable backwards compatibility for legacy peers
      if version < 5
        @offset_based_dispatch = true
        max_window_size = 2**32 # disable chunked transfers
      end

      # call peermanager
      agree = @peermanager.on_hello_received(proto, version, client_version_string, capabilities, listen_port, remote_pubkey)
      return unless agree

      @remote_client_version = client_version_string
      @remote_pubkey = remote_pubkey

      # register in common protocols
      logger.debug 'connecting services', services: @peermanager.wired_services
      remote_services = capabilities.map {|name, version| [name, version] }.to_h

      @peermanager.wired_services.sort_by(&:name).each do |service|
        raise PeerError, 'invalid service' unless service.is_a?(WiredService)

        proto = service.wire_protocol
        if remote_services.has_key?(proto.name)
          if remote_services[proto.name] == proto.version
            if service != @peermanager # p2p protocol already registered # FIXME: ???
              connect_service service
            end
          else
            logger.debug 'wrong version', service: proto.name, local_version: proto.version, remote_version: remote_services[proto.name]
            report_error 'wrong version'
          end
        end
      end
    end

    def capabilities
      @peermanager.wired_services.map {|s| [s.wire_protocol.name, s.wire_protocol.version] }
    end

    def send_packet(packet)
      protocol = @protocols.values.find {|pro| pro.protocol_id == packet.protocol_id }
      raise PeerError, "no protocol found" unless protocol
      logger.debug "send packet", cmd: protocol.cmd_by_id[packet.cmd_id], protocol: protocol.name, peer: self

      # rewrite cmd_id (backwards compatibility)
      if @offset_based_dispatch
        @protocols.values.each_with_index do |proto, i|
          if packet.protocol_id > i
            packet.cmd_id += (protocol.max_cmd_id == 0 ? 0 : protocol.max_cmd_id + 1)
          end
          if packet.protocol_id == protocol.protocol_id
            protocol = proto
            break
          end
          packet.protocol_id = 0
        end
      end

      @mux.add_packet packet
    end

    def send_data(data)
      return if data.nil? || data.empty?

      # FIXME: TODO: safe_to_read.clear

      @socket.write data
      logger.debug "wrote data", size: data.size, ts: Time.now

      safe_to_read.broadcast
    rescue # TODO: socket error and timeout error
      logger.debug "write error #{$!}"
      report_error "write error #{$!}"
      stop
    end

    def start
      @stopped = false
    end

    def stop
      if !stopped?
        @stopped = true
        logger.debug "stopped", peer: self

        @protocols.each_value {|proto| proto.stop }
        @peermanager.delete self
        terminate
      end
    end

    def stopped?
      @stopped
    end

    private

    def logger
      @logger ||= Logger.new 'p2p.peer'
    end

    def handle_packet(packet)
      raise ArgumentError, 'packet must be Packet' unless packet.is_a?(Packet)

      protocol, cmd_id = protocol_cmd_id_from_packet packet
      logger.debug "recv packet", cmd: protocol.cmd_by_id[cmd_id], protocol: protocol.name, orig_cmd_id: packet.cmd_id

      packet.cmd_id = cmd_id # rewrite
      protocol.receive_packet packet
    rescue UnknownCommandError
      logger.error 'received unknown cmd', error: e, packet: packet
    end

    def protocol_cmd_id_from_packet(packet)
      # offset-based dispatch (backwards compatibility)
      if @offset_based_dispatch
        max_id = 0

        @protocols.each_value do |protocol|
          if packet.cmd_id < max_id + protocol.max_cmd_id + 1
            return protocol, packet.cmd_id - (max_id == 0 ? 0 : max_id + 1)
            max_id += protocol.max_cmd_id
          end
        end
        raise UnknownCommandError, "no protocol for id #{packet.cmd_id}"
      end

      # new-style dispatch based on protocol_id
      @protocols.values.each_with_index do |protocol, i|
        if packet.protocol_id == protocol.protocol_id
          return protocol, packet.cmd_id
        end
      end
      raise UnknownCommandError, "no protocol for protocol id #{packet.protocol_id}"
    end

    ##
    # Stop peer if hello not received
    #
    def check_if_dumb_remote
      if !@hello_received
        report_error "No hello in #{DUMB_REMOTE_TIMEOUT} seconds"
        stop
      end
    end

    def run_egress_message
      while !stopped?
        send_data @mux.get_message
      end
    end

    def run_decoded_packets
      while !stopped?
        handle_packet @mux.get_packet # get_packet blocks
      end
    end

    def run_ingress_message
      logger.debug "peer starting main loop"
      raise PeerError, 'connection is closed' if @socket.closed?

      decode_packet_future = future { run_decoded_packets }
      egress_message_future = future { run_egress_message }

      while !stopped?
        safe_to_read.wait

        begin
        rescue # TODO: socket error
        end
      end
    end

  end

end
