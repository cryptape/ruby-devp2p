# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Discovery

    ##
    # Persist the list of known nodes with their reputation.
    #
    class Service < BaseService
      include ProtocolTransport

      name 'discovery'

      default_config(
        discovery: {
          listen_port: 30303,
          listen_host: '0.0.0.0'
        },
        node: {
          privkey_hex: ''
        }
      )

      attr :protocol

      def initialize(app)
        super(app)
        logger.info "Discovery service init"

        @server = nil # will be UDPSocket
        @protocol = Protocol.new app, self
      end

      def address
        ip = @app.config[:discovery][:listen_host]
        port = @app.config[:discovery][:listen_port]
        Address.new ip, port
      end

      def send_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)
        logger.debug "sending", size: message.size, to: address

        begin
          @server.send message, 0, address.ip, address.udp_port
        rescue
          # should never reach here? udp has no connection!
          logger.error "udp write error", error: $!
          logger.error "waiting for recovery"
          sleep 5
        end
      end

      def receive_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)
        @protocol.receive_message address, message
      end

      def start
        logger.info 'starting discovery'

        ip = @app.config[:discovery][:listen_host]
        port = @app.config[:discovery][:listen_port]

        logger.info "starting listener", port: port, host: ip

        @server = UDPSocket.new
        @server.bind ip, port

        super

        @protocol.bootstrap(
          @app.config[:discovery][:bootstrap_nodes].map {|x| Node.from_uri(x) }
        )
      end

      def run
        logger.debug "run called"

        maxlen = Multiplexer.max_window_size * 2
        loop do
          break if stopped?
          message, info = @server.recvfrom maxlen
          handle_packet message, info[3], info[1]
        end
      end

      def stop
        logger.info "stopping discovery"
        super
      end

      private

      def logger
        @logger ||= Logger.new 'p2p.discovery'
      end

      def handle_packet(message, ip, port)
        logger.debug "handling packet", ip: ip, port: port, size: message.size
        receive_message Address.new(ip, port), message
      end

    end

  end
end
