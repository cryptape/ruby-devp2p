# -*- encoding : ascii-8bit -*-

module DEVp2p

##
  # When sending a packet over RLPx, the packet will be framed. The frame
  # provides information about the size of the packet and the packet's source
  # protocol. There are three slightly different frames, depending on whether
  # or not the frame is delivering a multi-frame packet. A multi-frame packet
  # is a packet which is split (aka chunked) into multiple frames because it's
  # size is larger than the protocol window size (pws, see Multiplexing). When
  # a packet is chunked into multiple frames, there is an implicit difference
  # between the first frame and all subsequent frames.
  #
  # Thus, the three frame types are normal, chunked-0 (first frame of a
  # multi-frame packet), and chunked-n (subsequent frames of a multi-frame
  # packet).
  #
  # * Single-frame packet:
  #
  #   header || header-mac || frame || mac
  #
  # * Multi-frame packet:
  #
  #   header || header-mac || frame-0 ||
  #   [ header || header-mac || frame-n || ... || ]
  #   header || header-mac || frame-last || mac
  #
  class Frame

    extend Configurable
    add_config(
      header_size: 16,
      mac_size: 16,
      padding: 16,
      header_sedes: RLP::Sedes::List.new(elements: [RLP::Sedes.big_endian_int]*3, strict: false)
    )

    attr :protocol_id, :cmd_id, :sequence_id, :payload, :is_chunked_n, :total_payload_size, :frames

    def initialize(protocol_id, cmd_id, payload, sequence_id, window_size, is_chunked_n=false, frames=nil, frame_cipher=nil)
      raise ArgumentError, 'invalid protocol_id' unless protocol_id < TT16
      raise ArgumentError, 'invalid sequence_id' unless sequence_id.nil? || sequence_id < TT16
      raise ArgumentError, 'invalid window_size' unless window_size % self.class.padding == 0
      raise ArgumentError, 'invalid cmd_id' unless cmd_id < 256

      @protocol_id = protocol_id
      @cmd_id = cmd_id
      @payload = payload
      @sequence_id = sequence_id
      @is_chunked_n = is_chunked_n
      @frame_cipher = frame_cipher

      @frames = frames || []
      @frames.push self

      # chunk payloads resulting in frames exceeing window_size
      fs = frame_size
      if fs > window_size
        unless is_chunked_n
          @is_chunked_0 = true
          @total_payload_size = body_size
        end

        # chunk payload
        @payload = payload[0...(window_size-fs)]
        raise FrameError, "invalid frame size" unless frame_size <= window_size

        remain = payload[@payload.size..-1]
        raise FrameError, "invalid remain size" unless (remain.size + @payload.size) == payload.size

        Frame.new(protocol_id, cmd_id, remain, sequence_id, window_size, true, @frames, frame_cipher)
      end

      raise FrameError, "invalid frame size" unless frame_size <= window_size
    end

    def frame_type
      return :normal if normal?
      @is_chunked_n ? :chunked_n : :chunked_0
    end

    def frame_size
      # header16 || mac16 || dataN + [padding] || mac16
      self.class.header_size + self.class.mac_size + body_size(true) + self.class.mac_size
    end

    ##
    # frame-size: 3-byte integer, size of frame, big endian encoded (excludes
    # padding)
    #
    def body_size(padded=false)
      l = enc_cmd_id.size + payload.size
      padded ? Utils.ceil16(l) : l
    end

    def normal?
      !@is_chunked_n && !@is_chunked_0
    end

    ##
    # header: frame-size || header-data || padding
    #
    # frame-size: 3-byte integer, size of frame, big endian encoded
    # header-data:
    #   normal: RLP::Sedes::List.new(protocol_type[, sequence_id])
    #   chunked_0: RLP::Sedes::List.new(protocol_type, sequence_id, total_packet_size)
    #   chunked_n: RLP::Sedes::List.new(protocol_type, sequence_id)
    #   normal, chunked_n: RLP::Sedes::List.new(protocol_type[, sequence_id])
    #   values:
    #     protocol_type: < 2**16
    #     sequence_id: < 2**16 (this value is optional for normal frames)
    #     total_packet_size: < 2**32
    # padding: zero-fill to 16-byte boundary
    #
    def header
      raise FrameError, "invalid protocol id" unless protocol_id < 2**16
      raise FrameError, "invalid sequence id" unless sequence_id.nil? || sequence_id < TT16

      l = [protocol_id]
      if @is_chunked_0
        raise FrameError, 'chunked_0 must have sequence_id' if sequence_id.nil?
        l.push sequence_id
        l.push total_payload_size
      elsif sequence_id
        l.push sequence_id
      end

      header_data = RLP.encode l, sedes: self.class.header_sedes
      raise FrameError, 'invalid rlp' unless l == RLP.decode(header_data, sedes: self.class.header_sedes, strict: false)

      bs = body_size
      raise FrameError, 'invalid body size' unless bs < 256**3

      header = [body_size].pack('I>')[1..-1] + header_data
      header = Utils.rzpad16 header
      raise FrameError, 'invalid header' unless header.size == self.class.header_size

      header
    end

    def enc_cmd_id
      @is_chunked_n ? '' : RLP.encode(cmd_id, sedes: RLP::Sedes.big_endian_int)
    end

    ##
    # frame:
    #   normal: rlp(packet_type) [|| rlp(packet_data)] || padding
    #   chunked_0: rlp(packet_type) || rlp(packet_data ...)
    #   chunked_n: rlp(...packet_data) || padding
    # padding: zero-fill to 16-byte boundary (only necessary for last frame)
    #
    def body
      Utils.rzpad16 "#{enc_cmd_id}#{payload}"
    end

    def as_bytes
      raise FrameError, 'can only be called once' if @cipher_called

      if @frame_cipher
        @cipher_called = true
        e = @frame_cipher.encrypt(header, body)
        raise FrameError, 'invalid frame size of encrypted frame' unless e.size == frame_size
        e
      else
        h = header
        raise FrameError, 'invalid header size' unless h.size == self.class.header_size

        b = body
        raise FrameError, 'invalid body size' unless b.size == body_size(true)

        dummy_mac = "\x00" * self.class.mac_size
        r = h + dummy_mac + b + dummy_mac
        raise FrameError, 'invalid frame' unless r.size == frame_size

        r
      end
    end

    def to_s
      "<Frame(#{frame_type}, len=#{frame_size}, protocol=#{protocol_id} sid=#{sequence_id})"
    end
    alias :inspect :to_s


  end

end
