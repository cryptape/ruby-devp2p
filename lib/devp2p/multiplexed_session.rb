# -*- encoding : ascii-8bit -*-

module DEVp2p

  class MultiplexedSession < Multiplexer

    def initialize(privkey, hello_packet, remote_pubkey=nil)
      @hello_packet = hello_packet
      @remote_pubkey = remote_pubkey

      @message_queue = SyncQueue.new # wire msg egress queue
      @packet_queue = SyncQueue.new # packet ingress queue

      @is_initiator = !!remote_pubkey
      @handshake_finished = false

      ecc = Crypto::ECCx.new privkey
      @rlpx_session = RLPxSession.new ecc, @is_initiator

      super(@rlpx_session)

      send_init_msg if @is_initiator
    end

    def ready?
      @rlpx_session.ready?
    end

    def initiator?
      @is_initiator
    end

    def remote_pubkey
      @remote_pubkey || @rlpx_session.remote_pubkey
    end

    def remote_pubkey=(key)
      @remote_pubkey = key
    end

    def add_message(msg)
      @handshake_finished ? add_message_post_handshake(msg) : add_message_during_handshake(msg)
    end

    ##
    # encodes a packet and adds the message(s) to the message queue.
    #
    def add_packet(packet)
      raise MultiplexedSessionError, 'session is not ready' unless ready?
      raise ArgumentError, 'packet must be instance of Packet' unless packet.is_a?(Packet)

      super(packet)

      pop_all_frames.each {|f| @message_queue.enq f.as_bytes }
    end

    private

    def send_init_msg
      auth_msg = @rlpx_session.create_auth_message @remote_pubkey
      auth_msg_ct = @rlpx_session.encrypt_auth_message auth_msg

      @message_queue.enq auth_msg_ct
    end

    def add_message_during_handshake(msg)
      raise MultiplexedSessionError, 'handshake after ready is not allowed' if ready?

      if initiator?
        # expecting auth ack message
        rest = @rlpx_session.decode_auth_ack_message msg
        @rlpx_session.setup_cipher

        # add remains (hello) to queue
        add_message_post_handshake(rest) unless rest.empty?
      else
        # expecting auth_init
        rest = @rlpx_session.decode_authentication msg
        auth_ack_msg = @rlpx_session.create_auth_ack_message
        auth_ack_msg_ct = @rlpx_session.encrypt_auth_ack_message auth_ack_msg

        @message_queue.enq auth_ack_msg_ct

        @rlpx_session.setup_cipher
        add_message_post_handshake(rest) unless rest.empty?
      end

      @handshake_finished = true
      raise MultiplexedSessionError, 'session is not ready after handshake' unless @rlpx_session.ready?

      add_packet @hello_packet
    end

    def add_message_post_handshake(msg)
      decode(msg).each do |packet|
        @packet_queue.enq packet
      end
    end

  end

end
