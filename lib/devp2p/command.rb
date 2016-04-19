# -*- encoding : ascii-8bit -*-

module DEVp2p

  class Command

    extend Configurable
    add_config(
      cmd_id: 0,
      structure: {}, # {arg_name: RLP::Sedes.type}
      decode_strict: true
    )

    class <<self
      def encode_payload(data)
        if data.is_a?(Hash)
          raise ArgumentError, 'structure must be hash of arg names and sedes' unless structure.instance_of?(Hash)
          data = structure.keys.map {|k| data[k] }
        end

        case structure
        when RLP::Sedes::CountableList
          RLP.encode data, structure
        when Hash
          raise ArgumentError, 'structure and data length mismatch' unless data.size == structure.size
          RLP.encode data, sedes: RLP::Sedes::List.new(elements: sedes)
        else
          raise InvalidCommandStructure
        end
      end

      def decode_payload(rlp_data)
        case structure
        when RLP::Sedes::CountableList
          decoder = structure
        when Hash
          decoder = RLP::Sedes::List.new(elements: sedes, strict: decode_strict)
        else
          raise InvalidCommandStructure
        end

        data = RLP.decode rlp_data, sedes: decoder
        data = structure.keys.zip(data).to_h if structure.is_a?(Hash)
        data
      rescue
        puts "error in decode: #{$!}"
        puts "rlp:"
        puts RLP.decode(rlp_data)
        raise $!
      end

      def sedes
        @sedes ||= structure.values
      end
    end

    attr :receive_callbacks

    def initialize
      raise InvalidCommandStructure unless [Hash, RLP::Sedes::CountableList].any? {|c| self.class.structure.is_a?(c) }
      @receive_callbacks = []
    end

    # optionally implement create
    def create(proto, *args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      raise ArgumentError, "proto must be protocol" unless proto.is_a?(BaseProtocol)
      raise ArgumentError, "command structure mismatch" if !options.empty? && self.class.structure.instance_of?(RLP::Sedes::CountableList)
      options.empty? ? args : options
    end

    # optionally implement receive
    def receive(proto, data)
      if self.class.structure.instance_of?(RLP::Sedes::CountableList)
        receive_callbacks.each {|cb| cb.call(proto, data) }
      else
        receive_callbacks.each {|cb| cb.call(proto, **data) }
      end
    end
  end

end
