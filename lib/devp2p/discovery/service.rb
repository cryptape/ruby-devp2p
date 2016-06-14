# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Discovery

    class Receiver
      include Concurrent::Async

      def initialize(service, socket)
        super()

        @service = service
        @socket = socket
      end

      def start
        maxlen = Multiplexer.max_window_size * 2

        loop do
          break if @stopped || @socket.closed?

          puts "*"*100
          p 'yes'
          message, info = @socket.recvfrom maxlen
          p 'hooo!'
          handle_packet message, info[3], info[1]
        end
      rescue
        puts $!
        puts $!.backtrace[0,10].join("\n")
      end

      def stop
        @stopped = true
      end

      def handle_packet(message, ip, port)
        logger.debug "handling packet", ip: ip, port: port, size: message.size
        @service.async.receive_message Address.new(ip, port), message
      end
    end

    class Sender
      include Concurrent::Async

      def initialize(service, socket)
        super()

        @service = service
        @socket = socket
      end

      def start
        # do nothing
      end

      def send_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)
        logger.debug "sending", size: message.size, to: address

        @socket.send message, 0, address.ip, address.udp_port
      end
    end

    class Service < ::DEVp2p::Service
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

        @socket = nil
        @protocol = Protocol.new app, self
      end

      def start
        logger.info 'starting discovery'

        ip = @app.config[:discovery][:listen_host]
        port = @app.config[:discovery][:listen_port]

        logger.info "starting udp listener", port: port, host: ip

        @socket = UDPSocket.new
        @socket.bind ip, port

        @receiver = Receiver.new self, @socket
        @sender = Sender.new self, @socket
        @receiver.async.start
        @sender.async.start

        nodes = @app.config[:discovery][:bootstrap_nodes] || []
        @protocol.bootstrap( nodes.map {|x| Node.from_uri(x) } )
      rescue
        puts $!
        puts $!.backtrace[0,10].join("\n")
      end

      def stop
        logger.info "stopping discovery"

        @socket.close if @socket
        @sender.async.stop if @sender
        @receiver.async.stop if @receiver

        @socket = nil
        @sender = nil
        @receiver = nil
      end

      def address
        ip = @app.config[:discovery][:listen_host]
        port = @app.config[:discovery][:listen_port]
        Address.new ip, port
      end

      def receive_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.instance_of?(Address)
        @protocol.receive_message address, message
      end

      def send_message(address, message)
        @sender.async.send_message address, message
      end

      private

      def logger
        @logger ||= Logger.new "#{@app.config[:discovery][:listen_port]}.p2p.discovery"
      end

    end

  end
end
