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

      def initialize(app)
        super(app)
        logger.info "Discovery service init"

        @server = nil # will be DatagramServer
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
          @server.sendto message, [address.ip, address.udp_port]
        rescue # TODO: socket.error
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

        @server = DatagramServer.new([ip, port]) do |message, ip_port|
          logger.debug "handling packet", address: ip_port, size: message.size
          raise ArgumentError, 'invalid ip_port' unless ip_port.size == 2
          receive_message Address.new(*ip_port), message
        end
        @server.start

        super

        @protocol.bootstrap(
          @app.config[:discovery][:bootstrap_nodes].map {|x| Node.from_uri(x) }
        )
      end

      def run
        logger.debug "run called"
        cond = Celluloid::Condition.new
        cond.wait
      end

      def stop
        logger.info "stopping discovery"
        @server.stop
        super
      end

    end

  end
end
