# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # connection strategy
  #   for service which requires peers
  #     while peers.size > min_num_peers
  #       gen random id
  #       resolve closest node address
  #       [ideally know their services]
  #       connect closest node
  #
  class PeerManager < WiredService
    include Celluloid::IO
    finalizer :cleanup

    name 'peermanager'
    required_services []

    default_config(
      p2p: {
        bootstrap_nodes: [],
        min_peers: 5,
        max_peers: 10,
        listen_port: 30303,
        listen_host: '0.0.0.0'
      },
      log_disconnects: false,
      node: {privkey_hex: ''}
    )

    def initialize(app)
      logger.info "PeerManager init"
      super(app)

      @peers = []
      @errors = @config[:log_disconnects] ? PeerErrors.new : PeerErrorsBase.new

      @wire_protocol = P2PProtocol

      # setup nodeid based on privkey
      unless @config[:p2p].has_key?(:id)
        @config[:node][:id] = Crypto.privtopub Utils.decode_hex(@config[:node][:privkey_hex])
      end

      @connect_timeout = 2.0
      @connect_loop_delay = 0.1
      @discovery_delay = 0.5

      @host = @config[:p2p][:listen_host]
      @port = @config[:p2p][:listen_port]
    end

    def start
      logger.info "starting peermanager"

      logger.info "starting listener", host: @host, port: @port
      @server = TCPServer.new @host, @port

      super
      after(0.01) { discovery_loop }
    end

    def stop
      logger.info "stopping peermanager"

      @server.close if @server
      @peers.each(&:stop)

      super
    end

    def _run
      loop do
        break if stopped?
        async.handle_connection @server.accept
      end
    rescue IOError
      logger.error "listening error: #{$!}"
      puts $!
      @stopped = true
    end

    def add(peer)
      @peers.push peer
      #link peer
    end

    def delete(peer)
      @peers.delete peer
    end

    def on_hello_received(proto, version, client_version_string, capabilities, listen_port, remote_pubkey)
      logger.debug 'hello_received', peer: proto.peer, num_peers: @peers.size

      extra_peers = @peers[0,@config[:p2p][:max_peers]]
      if extra_peers.include?(proto.peer)
        logger.debug "too many peers", max: @config[:p2p][:max_peers]
        proto.send_disconnect proto.class::Disconnect::Reason[:too_many_peers]
        return false
      end
      if @peers.select {|p| p != proto.peer }.include?(remote_pubkey)
        logger.debug "connected to that node already"
        proto.send_disconnect proto.class::Disconnect::Reason[:useless_peer]
        return false
      end

      return true
    end

    def wired_services
      app.services.values.select {|s| s.is_a?(WiredService) }
    end

    def broadcast(protocol, command_name, args=[], kwargs={}, num_peers=nil, exclude_peers=[])
      logger.debug "broadcasting", protocol: protocol, command: command_name, num_peers: num_peers, exclude_peers: exclude_peers
      raise ArgumentError, 'invalid num_peers' unless num_peers.nil? || num_peers > 0

      peers_with_proto = @peers.select {|p| p.protocols.include?(protocol) && !exclude_peers.include?(p) }
      if peers_with_proto.empty?
        logger.debug "no peers with protocol found", protos: @peers.select {|p| p.protocols }
      end

      num_peers ||= peers_with_proto.size
      peers_with_proto.sample([num_peers, peers_with_proto.size].min).each do |peer|
        logger.debug "broadcasting to", proto: peer.protocols[protocol]

        args.push kwargs
        peer.protocols[protocol].send "send_#{command_name}", *args

        peer.safe_to_read.wait
        logger.debug "broadcasting done", ts: Time.now
      end
    end

    ##
    # Connect to address (a 2-tuple [host, port]) and return the socket object.
    #
    # Passing the optional timeout parameter will set the timeout.
    #
    def connect(host, port, remote_pubkey)
      socket = create_connection host, port, @connect_timeout
      logger.debug "connecting to", peer: socket.peeraddr

      start_peer socket, remote_pubkey
      true
    rescue Errno::ETIMEDOUT
      address = "#{host}:#{port}"
      logger.debug "connection timeout", address: address, timeout: @connect_timeout
      @errors.add address, 'connection timeout'
      false
    rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ECONNREFUSED
      address = "#{host}:#{port}"
      logger.debug "connection error #{$!}"
      @errors.add address, "connection error #{$!}"
      false
    end

    def num_peers
      active = @peers.select {|p| !p.stopped? }

      if @peers.size != active.size
        logger.error "stopped peers in peers list", inlist: @peers.size, active: active.size
      end

      active.size
    end

    def add_error(*args)
      @errors.add *args
    end

    private

    def logger
      @logger ||= Logger.new 'p2p.peermgr'
    end

    def bootstrap(bootstrap_nodes=[])
      bootstrap_nodes.each do |uri|
        ip, port, pubkey = Utils.host_port_pubkey_from_uri uri
        logger.info 'connecting bootstrap server', uri: uri

        begin
          connect ip, port, pubkey
        rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ETIMEDOUT
          logger.warn "connecting bootstrap server failed: #{$!}"
        end
      end
    end

    def handle_connection(socket)
      _, port, host = socket.peeraddr
      logger.debug "incoming connection", host: host, port: port

      peer = start_peer socket
      #Celluloid::Actor.join peer
    rescue EOFError
      logger.debug "connection disconnected", host: host, port: port
      socket.close
    end

    # FIXME: TODO: timeout is ignored!
    def create_connection(host, port, timeout)
      Celluloid::IO::TCPSocket.new ::TCPSocket.new(host, port)
    end

    def start_peer(socket, remote_pubkey=nil)
      peer = Peer.new Actor.current, socket, remote_pubkey
      logger.debug "created new peer", peer: peer, fileno: socket.to_io.fileno

      add peer
      peer.start

      logger.debug "peer started", peer: peer, fileno: socket.to_io.fileno
      raise PeerError, 'connection closed' if socket.closed?

      peer
    end

    def discovery_loop
      logger.info "waiting for bootstrap"
      sleep @discovery_delay

      while !stopped?
        num, min = num_peers, @config[:p2p][:min_peers]

        begin
          kademlia_proto = app.services.discovery.protocol.kademlia
        rescue NoMethodError # some point hit nil
          logger.error "Discovery service not available."
          break
        end

        if num < min
          logger.debug "missing peers", num_peers: num, min_peers: min, known: kademlia_proto.routing.size

          nodeid = Kademlia.random_nodeid

          kademlia_proto.find_node nodeid
          sleep @discovery_delay

          neighbours = kademlia_proto.routing.neighbours(nodeid, 2)
          if neighbours.empty?
            sleep @connect_loop_delay
            next
          end

          node = neighbours.sample
          logger.debug 'connecting random', node: node

          local_pubkey = Crypto.privtopub Utils.decode_hex(@config[:node][:privkey_hex])
          next if node.pubkey == local_pubkey
          next if @peers.any? {|p| p.remote_pubkey == node.pubkey }

          connect node.address.ip, node.address.tcp_port, node.pubkey
        end

        sleep @connect_loop_delay
      end

      # TODO: ???
      cond = Celluloid::Condition.new
      cond.wait
    end

    def cleanup
      @server.close if @server && !@server.closed?
    end

  end

end
