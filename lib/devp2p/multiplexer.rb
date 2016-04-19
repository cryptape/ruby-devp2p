# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # Multiplexing of protocols is performed via dynamic framing and fair
  # queueing. Dequeuing packets is performed in a cycle which dequeues one or
  # more packets from the queue(s) of each active protocol. The multiplexor
  # determines the amount of bytes to send for each protocol prior to each
  # round of dequeuing packets.
  #
  # If the size of an RLP-encoded packet is less than 1KB then the protocol may
  # request that the network layer prioritize the delivery of the packet. This
  # should be used if and only if the packet must be delivered before all other
  # packets.
  #
  # The network layer maintains two queues and three buffers per protocol:
  #
  # * a queue for normal packets, a queue for priority packets
  # * a chunked-frame buffer, a normal-frame buffer, and a priority-frame buffer
  #
  # Implemented Variant:
  #
  # each sub protocol has three queues: prio, normal, chunked
  #
  # protocols are queried round robin
  #
  class Multiplexer

    extend Configurable
    add_config(
      max_window_size: 8 * 1024,
      max_priority_frame_size: 1024,
      max_payload_size: 10 * 1024**2,
      frame_cipher: nil,
    )

    attr :decode_buffer

    def initialize(frame_cipher=nil)
      @frame_cipher = frame_cipher || self.class.frame_cipher
      @last_protocol = nil
      @decode_buffer = "" # byte array

      # protocol_id: {normal: queue, chunked: queue, prio: queue}
      @queues = {}

      # protocol_id: counter
      @sequence_id = {}

      # decode: {protocol_id: {sequence_id: buffer}
      @chunked_buffers = {}
    end

    ##
    # A protocol is considered active if it's queue contains one or more
    # packets.
    #
    def num_active_protocols
      @queues.keys.select {|id| active_protocol?(id) }.size
    end

    def active_protocol?(id)
      !@queues[id].values.all?(&:empty?)
    end

    # pws = protocol_window_size = window_size / active_protocol_count
    def protocol_window_size(id=nil)
      if id && !active_protocol?(id)
        s = self.class.max_window_size / (1 + num_active_protocols)
      else
        s = self.class.max_window_size / [1, num_active_protocols].max
      end

      s - s % 16 # should be a multiple of padding size # FIXME: 16 should be constant
    end

    def add_protocol(id)
      raise ArgumentError, 'protocol already added' if @queues.include?(id)

      @queues[id] = {
        normal: SyncQueue.new,
        chunked: SyncQueue.new,
        priority: SyncQueue.new
      }
      @sequence_id[id] = 0
      @chunked_buffers[id] = {}
      @last_protocol = id
    end

    def next_protocol
      protocols = @queues.keys
      if @last_protocol == protocols.last
        proto = protocols.first
      else
        proto = protocols[protocols.index(@last_protocol) + 1]
      end

      @last_protocol = proto
      proto
    end

    def add_packet(packet)
      sid = @sequence_id[packet.protocol_id]
      @sequence_id[packet.protocol_id] = (sid + 1) % TT16

      frames = Frame.new(
        packet.protocol_id, packet.cmd_id, packet.payload, sid,
        protocol_window_size(packet.protocol_id),
        false, nil, @frame_cipher
      ).frames

      queues = @queues[packet.protocol_id]

      if packet.prioritize
        raise FrameError, "invalid priority packet frames" unless frames.size == 1
        raise FrameError, "frame too large for priority packet" unless frames[0].frame_size <= self.class.max_priority_frame_size

        queues[:priority].enq frames[0]
      elsif frames.size == 1
        queues[:normal].enq frames[0]
      else
        frames.each {|f| queues[:chunked].enq f }
      end
    end

    ##
    # If priority packet and normal packet exist:
    #   send up to pws/2 bytes from each (priority first)
    # else if priority packet and chunked-frame exist:
    #   send up to pws/2 bytes from each
    # else if normal packet and chunked-frame exist:
    #   send up to pws/2 bytes from each
    # else
    #   read pws bytes from active buffer
    #
    # If there are bytes leftover -- for example, if the bytes sent is < pws,
    # then repeat the cycle.
    #
    def pop_frames_for_protocol(id)
      pws = protocol_window_size
      queues = @queues[id]

      frames = []
      size = 0

      while size < pws
        frames_added = 0

        %i(priority normal chunked).each do |qn|
          q = queues[qn]

          if !q.empty?
            fs = q.peek.frame_size
            if size + fs <= pws
              frames.push q.deq
              size += fs
              frames_added += 1
            end
          end

          # add no more than two in order to send normal and priority first
          # i.e. next is 'priority' again
          #
          # FIXME: too weird
          #
          break if frames_added == 2
        end

        break if frames_added == 0 # empty queues
      end

      # the following can not be guaranteed, as pws might have been different
      # at the time where packets were framed and added to the queues
      #
      #   frames.map(&:frame_size).sum <= pws
      return frames
    end

    ##
    # Returns the frames for the next protocol up to protocol window size bytes.
    #
    def pop_frames
      protocols = @queues.keys
      idx = protocols.index next_protocol
      protocols = protocols[idx..-1] + protocols[0,idx]

      protocols.each do |id|
        frames = pop_frames_for_protocol id
        return frames unless frames.empty?
      end

      []
    end

    def pop_all_frames
      frames = []
      loop do
        r = pop_frames
        frames.concat r
        break if r.empty?
      end
      frames
    end

    def pop_all_frames_as_bytes
      pop_all_frames.map(&:as_bytes).join
    end

    def decode_header(buffer)
      raise ArgumentError, "buffer too small" unless buffer.size >= 32

      if @frame_cipher
        header = @frame_cipher.decrypt_header(buffer[0, Frame.header_size + Frame.mac_size])
      else
        # header: frame-size || header-data || padding
        header = buffer[0, Frame.header_size]
      end

      header
    end

    ##
    # w/o encryption
    # peak info buffer for body_size
    #
    # return nil if buffer is not long enough to decode frame
    #
    def decode_body(buffer, header=nil)
      return [nil, buffer] if buffer.size < Frame.header_size

      header ||= decode_header buffer[0, Frame.header_size + Frame.mac_size]
      body_size = Frame.decode_body_size header

      if @frame_cipher
        body = @frame_cipher.decrypt_body(buffer[(Frame.header_size+Frame.mac_size)..-1], body_size)
        raise MultiplexerError, 'body length mismatch' unless body.size == body_size

        bytes_read = Frame.header_size + Frame.mac_size + Utils.ceil16(body.size) + Frame.mac_size
      else
        header = buffer[0, Frame.header_size]
        body_offset = Frame.header_size + Frame.mac_size
        body = buffer[body_offset, body_size]
        raise MultiplexerError, 'body length mismatch' unless body.size == body_size

        bytes_read = Utils.ceil16(body_offset + body_size + Frame.mac_size)
      end
      raise MultiplexerError, "bytes not padded" unless bytes_read % Frame.padding == 0

      # normal, chunked-n: RLP::List.new(protocol_type[, sequence_id])
      # chunked-0: RLP::List.new(protocol_type, sequence_id, total_packet_size)
      header_data = nil
      begin
        header_data = RLP.decode(header[3..-1], sedes: Frame.header_sedes, strict: false)
      rescue RLP::Error::RLPException => e
        logger.error(e)
        raise MultiplexerError, 'invalid rlp data'
      end

      if header_data.size == 3
        chunked_0 = true
        total_payload_size = header_data[2]
        raise MultiplexerError, "invalid total payload size" unless total_payload_size < 2**32
      else
        chunked_0 = false
        total_payload_size = nil
      end

      protocol_id = header_data[0]
      raise MultiplexerError, "invalid protocol id" unless protocol_id < TT16

      if header_data.size > 1
        sequence_id = header_data[1]
        raise MultiplexerError, "invalid sequence id" unless sequence_id < TT16
      else
        sequence_id = nil
      end

      raise MultiplexerError, "unknown protocol id #{protocol_id}" unless @chunked_buffers.has_key?(protocol_id)

      chunkbuf = @chunked_buffers[protocol_id]
      if chunkbuf.has_key?(sequence_id)
        packet = chunkbuf[sequence_id]

        raise MultiplexerError, "received chunked_0 frame for existing buffer #{sequence_id} of protocol #{protocol_id}" if chunked_0
        raise MultiplexerError, "too much data for chunked buffer #{sequence_id} of protocol #{protocol_id}" if body.size > (packet.total_payload_size - packet.payload.size)

        packet.payload += body
        if packet.total_payload_size == packet.payload.size
          packet.total_payload_size = nil
          chunkbuf.delete sequence_id
          return packet
        end
      else
        # body of normal, chunked_0: rlp(packet-type) [|| rlp(packet-data)] || padding
        item, item_end = RLP.consume_item(body, 0)
        cmd_id = RLP::Sedes.big_endian_int.deserialize item

        if chunked_0
          payload = body[item_end..-1]
          total_payload_size -= item_end
        else
          payload = body[item_end..-1]
        end

        packet = Packet.new protocol_id, cmd_id, payload
        if chunked_0
          raise MultiplexerError, "total payload size smaller than initial chunk" if total_payload_size < payload.size

          # shouldn't have been chunked, whatever
          return packet if total_payload_size == payload.size

          raise MultiplexerError, 'chunked_0 must have sequence id' if sequence_id.nil?

          packet.total_payload_size = total_payload_size
          chunkbuf[sequence_id] = packet

          return nil
        else
          return packet # normal (non-chunked)
        end
      end
    end

    def decode(data='')
      @decode_buffer.concat(data) unless data.empty?

      unless @cached_decode_header
        if @decode_buffer.size < Frame.header_size + Frame.mac_size
          return []
        else
          @cached_decode_header = decode_header @decode_buffer
        end
      end

      body_size = Frame.decode_body_size @cached_decode_header
      required_len = Frame.header_size + Frame.mac_size + Utils.ceil16(body_size) + Frame.mac_size

      if @decode_buffer.size >= required_len
        packet = decode_body @decode_buffer, @cached_decode_header
        @cached_decode_header = nil
        @decode_buffer = @decode_buffer[required_len..-1]

        return packet ? ([packet] + decode) : decode
      end

      []
    end

    private

    def logger
      @logger ||= Logger.new('multiplexer')
    end

  end

end
