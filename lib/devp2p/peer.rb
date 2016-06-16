# -*- encoding : ascii-8bit -*-

module DEVp2p

  class Peer
    include Concurrent::Async

    DUMB_REMOTE_TIMEOUT = 10.0

    attr :config, :protocols, :remote_client_version, :remote_pubkey

    def initialize(peermanager, socket, remote_pubkey=nil)
      @peermanager = peermanager
      @socket = socket
      @config = peermanager.config

      @protocols = {}

      @stopped = false
      @hello_received = false

      _, @port, _, @ip = @socket.peeraddr
      @remote_client_version = ''
      logger.debug "peer init", peer: self

      privkey = Utils.decode_hex @config[:node][:privkey_hex]
      hello_packet = P2PProtocol.get_hello_packet hello_data

      @mux = MultiplexedSession.new privkey, hello_packet, remote_pubkey
      @remote_pubkey = remote_pubkey

      connect_service @peermanager

      # assure, we don't get messages while replies are not read
      @safe_to_read = Concurrent::Event.new
      @safe_to_read.set

      # stop peer if hello not received in DUMB_REMOTE_TIMEOUT
      Concurrent::ScheduledTask.execute(DUMB_REMOTE_TIMEOUT) { check_if_dumb_remote }
    end

    def start
      @stopped = false
      @run = Thread.new { run }
    end

    def stop
      if !stopped?
        @stopped = true

        @protocols.each_value {|proto| proto.async.stop }
        @peermanager.async.delete self

        logger.info "peer stopped", peer: self
        @run.kill
        @run_decoded_packets.kill
        @run_egress_message.kill
      end
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    def stopped?
      @stopped
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
      pn = "#@ip:#@port"
      cv = @remote_client_version.split('/')[0,2].join('/')
      pn = "#{pn} #{cv}" unless cv.empty?
      "<Peer #{pn}>"
    end
    alias inspect to_s

    def report_error(reason)
      pn = "#@ip:#@port"
      @peermanager.add_error pn, reason, @remote_client_version
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

    def receive_hello(proto, data)
      version = data[:version]
      listen_port = data[:listen_port]
      capabilities = data[:capabilities]
      remote_pubkey = data[:remote_pubkey]
      client_version_string = data[:client_version_string]

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
            if service != @peermanager # p2p protocol already registered
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

      @safe_to_read.reset

      @socket.write data
      logger.debug "wrote data", size: data.size

      @safe_to_read.set
    rescue Errno::ETIMEDOUT
      logger.debug "write timeout"
      report_error "write timeout"
      stop
    rescue SystemCallError => e
      logger.debug "write error #{e}"
      report_error "write error #{e}"
      stop
    end

    def run
      logger.debug "peer starting main loop"
      raise PeerError, 'connection is closed' if @socket.closed?

      @run_decoded_packets = Thread.new { run_decoded_packets }
      @run_egress_message = Thread.new { run_egress_message }

      while !stopped?
        @safe_to_read.wait

        begin
          imsg = @socket.recv(4096)
          if imsg.empty?
            logger.info "socket closed"
            stop
          end
        rescue EOFError # imsg is empty
          if @socket.closed?
            logger.info "socket closed"
            stop
          else
            imsg = ''
          end
        rescue SystemCallError => e
          logger.debug "read error", error: e, peer: self
          report_error "network error #{e}"
          if [Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETDOWN, Errno::EHOSTUNREACH].any? {|syserr| e.instance_of?(syserr) }
            stop
          else
            raise e
            break
          end
        end

        if !imsg.empty?
          logger.debug "read data", size: imsg.size
          @mux.add_message imsg
        end
      end
    rescue RLPxSessionError, DecryptionError => e
      logger.debug "rlpx session error", peer: self, error: e
      report_error "rlpx session error"
      stop
    rescue MultiplexerError => e
      logger.debug "multiplexer error", peer: self, error: e
      report_error "multiplexer error"
      stop
    rescue
      logger.debug "ingress message error", peer: self, error: $!
      report_error "ingress message error"
      stop
    end

    private

    def logger
      @logger ||= Logger.new "p2p.peer"
    end

    def hello_data
      { client_version_string: config[:client_version_string],
        capabilities: capabilities,
        listen_port: config[:p2p][:listen_port],
        remote_pubkey: config[:node][:id]
      }
    end

    def handle_packet(packet)
      raise ArgumentError, 'packet must be Packet' unless packet.is_a?(Packet)

      protocol, cmd_id = protocol_cmd_id_from_packet packet
      logger.debug "recv packet", cmd: protocol.cmd_by_id[cmd_id], protocol: protocol.name, orig_cmd_id: packet.cmd_id

      packet.cmd_id = cmd_id # rewrite
      protocol.receive_packet packet
    rescue UnknownCommandError => e
      logger.error 'received unknown cmd', error: e, packet: packet
    rescue
      logger.error $!
      logger.error $!.backtrace[0,10].join("\n")
    end

    def protocol_cmd_id_from_packet(packet)
      # offset-based dispatch (backwards compatibility)
      if @offset_based_dispatch
        max_id = 0

        @protocols.each_value do |protocol|
          if packet.cmd_id < max_id + protocol.max_cmd_id + 1
            return protocol, packet.cmd_id - (max_id == 0 ? 0 : max_id + 1)
          end
          max_id += protocol.max_cmd_id
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
        # TODO: async.send_data?
        send_data @mux.get_message
      end
    end

    def run_decoded_packets
      while !stopped?
        # TODO: async.handle_packet?
        handle_packet @mux.get_packet # get_packet blocks
      end
    end

  end

end
