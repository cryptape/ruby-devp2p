# -*- encoding : ascii-8bit -*-

module DEVp2p

  class Command

    extend Configurable
    add_config(
      cmd_id: 0,
      structure: [], # [[arg_name, RLP::Sedes.type], ...]
      decode_strict: true
    )

    class <<self
      def encode_payload(data)
        if data.is_a?(Hash)
          raise ArgumentError, 'structure must be array of arg names and sedes' unless structure.instance_of?(Array)
          data = structure.map {|x| data[x[0]] }
        end

        case structure
        when RLP::Sedes::CountableList
          RLP.encode data, structure
        when Array
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
        when Array
          decoder = RLP::Sedes::List.new(elements: sedes, strict: decode_strict)
        else
          raise InvalidCommandStructure
        end

        data = RLP.decode rlp_data, sedes: decoder
        data = data.each_with_index.map {|v, i| [structure[i][0], v] }.to_h if structure.instance_of?(Array)
        data
      rescue
        puts "error in decode: #{$!}"
        puts "rlp:"
        puts RLP.decode(rlp_data)
        raise $!
      end

      def sedes
        @sedes ||= structure.map {|x| x[1] }
      end
    end

    attr :receive_callbacks

    def initialize
      raise InvalidCommandStructure unless [Array, RLP::Sedes::CountableList].include?(self.class.structure.class)
      @receive_callbacks = []
    end

    # optionally implement create
    def create(proto, *args, **kwargs)
      raise ArgumentError, "proto must be protocol" unless proto.is_a?(BaseProtocol)
      raise ArgumentError, "command structure mismatch" if !kwargs.empty? && self.class.structure.instance_of?(RLP::Sedes::CountableList)
      kwargs.empty? ? args : kwargs
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
