# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # Packets are emitted and received by subprotocols.
  #
  class Packet

    attr :protocol_id, :cmd_id, :prioritize

    attr_accessor :payload, :total_payload_size

    def initialize(protocol_id, cmd_id, payload, prioritize=false)
      @protocol_id = protocol_id
      @cmd_id = cmd_id
      @payload = payload
      @prioritize = prioritize
    end

    def to_s
      "Packet(protocol_id=#{protocol_id} cmd_id=#{cmd_id} payload_size=#{payload.size} prioritize=#{prioritize})"
    end

    def ==(other)
      protocol_id == other.protocol_id &&
        cmd_id == other.cmd_id &&
        payload == other.payload
    end

    def size
      payload.size
    end
    alias :length :size
  end

end
