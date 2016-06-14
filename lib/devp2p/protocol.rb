# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # A protocol mediates between the network and the service. It implements a
  # collection of commands.
  #
  # For each command X the following methods are created at initialization:
  #
  # * `packet = protocol.create_X(*args, **kwargs)`
  # * `protocol.send_X(*args, **kwargs)`, which is a shortcut for `send_packet`
  #   plus `create_X`.
  # * `protocol.receive_X(data)`
  #
  # On `protocol.receive_packet`, the packet is deserialized according to the
  # `command.structure` and the `command.receive` method called with a hash
  # containing the received data.
  #
  # The default implementation of `command.receive` calls callbacks which can
  # be registered in a list which is available as: `protocol.receive_X_callbacks`.
  #
  class Protocol
    include Concurrent::Async

    extend Configurable
    add_config(
      name: '',
      protocol_id: 0,
      version: 0,
      max_cmd_id: 0 # reserved cmd space
    )

    attr :peer, :service, :cmd_by_id

    def initialize(peer, service)
      raise ArgumentError, 'service must be WiredService' unless service.is_a?(WiredService)
      raise ArgumentError, 'peer.send_packet must be callable' unless peer.respond_to?(:send_packet)

      @peer = peer
      @service = service

      @stopped = false

      setup
    end

    def start
      logger.debug 'starting', proto: self
      service.await.on_wire_protocol_start self
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    def stop
      logger.debug 'stopping', proto: self
      service.await.on_wire_protocol_stop self

      @stopped = true
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    def receive_packet(packet)
      cmd_name = @cmd_by_id[packet.cmd_id]
      cmd = "receive_#{cmd_name}"
      send cmd, packet
    rescue ProtocolError => e
      logger.warn "protocol exception, stopping", error: e
      stop
    end

    def send_packet(packet)
      peer.async.send_packet packet
    end

    def to_s
      "<#{name} #{peer}>"
    end
    alias :inspect :to_s

    private

    def logger
      @logger ||= Logger.new('protocol')
    end

    def setup
      klasses = []
      self.class.constants.each do |name|
        c = self.class.const_get name
        klasses.push(c) if c.instance_of?(Class) && c < Command
      end

      raise DuplicatedCommand unless klasses.map(&:cmd_id).uniq.size == klasses.size

      proto = self

      klasses.each do |klass|
        instance = klass.new

        # decode rlp, create hash, call receive
        receive = lambda do |packet|
          raise ArgumentError unless packet.is_a?(Packet)
          instance.receive proto, klass.decode_payload(packet.payload)
        end

        # get data, rlp encode, return packet
        create = lambda do |*args|
          res = instance.create(proto, *args)
          payload = klass.encode_payload res
          Packet.new protocol_id, klass.cmd_id, payload
        end

        # create and send packet
        send_packet = lambda do |*args|
          packet = create.call *args
          send_packet packet
        end

        name = Utils.class_to_cmd_name(klass)
        singleton_class.send(:define_method, "receive_#{name}", &receive)
        singleton_class.send(:define_method, "create_#{name}", &create)
        singleton_class.send(:define_method, "send_#{name}", &send_packet)
        singleton_class.send(:define_method, "receive_#{name}_callbacks") do
          instance.receive_callbacks
        end
      end

      @cmd_by_id = klasses.map {|k| [k.cmd_id, Utils.class_to_cmd_name(k)] }.to_h
    end

  end

end
