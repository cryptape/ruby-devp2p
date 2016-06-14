# -*- encoding : ascii-8bit -*-
require 'test_helper'

class MultiplexedSessionTest < Minitest::Test
  include DEVp2p

  class PeerMock
    attr :config, :capabilities

    def initialize
      @config = Hashie::Mash.new(
        p2p: {listen_port: 3000},
        node: {id: "\x00"*64 },
        client_version_string: 'devp2p 0.0.0'
      )
      @capabilities = [['p2p', 2], ['eth', 57]]
    end

    def mock1(x); end
    alias :receive_hello :mock1
    alias :send_packet :mock1
    alias :stop :mock1
  end

  def test_session
    proto = P2PProtocol.new PeerMock.new, WiredService.new(App.new)
    hello_packet = proto.create_hello
    p0 = 0

    responder_privkey = Crypto.mk_privkey 'secret1'
    responder_pubkey = Crypto.privtopub responder_privkey
    responder = MultiplexedSession.new responder_privkey, hello_packet
    responder.add_protocol p0

    initiator_privkey = Crypto.mk_privkey 'secret2'
    initiator = MultiplexedSession.new initiator_privkey, hello_packet, responder_pubkey
    initiator.add_protocol p0

    # send auth
    msg = ivget(initiator, :@message_queue).deq(true)
    assert msg # <- send_init_msg
    assert ivget(initiator,:@packet_queue).empty?
    assert !responder.initiator?

    # receive auth
    responder.add_message msg
    assert ivget(responder, :@packet_queue).empty?
    assert responder.ready?

    # send auth ack and hello
    ack_msg = ivget(responder, :@message_queue).deq(true)
    hello_msg = ivget(responder, :@message_queue).deq(true)
    assert hello_msg

    # receive auth ack and hello
    initiator.add_message ack_msg + hello_msg
    assert initiator.ready?
    hello_packet = ivget(initiator, :@packet_queue).deq(true) # from responder
    assert hello_packet.instance_of?(Packet)

    # initiator sends hello
    hello_msg = ivget(initiator, :@message_queue).deq(true) # from initiator's own
    assert hello_msg

    # hello received by responder
    responder.add_message hello_msg
    hello_packet = ivget(responder, :@packet_queue).deq(true)
    assert hello_packet.instance_of?(Packet)

    # assert we received an actual hello packet
    data = proto.class::Hello.decode_payload hello_packet.payload
    assert_equal 4, data[:version]

    # test normal operation
    ping = proto.create_ping
    initiator.add_packet ping
    msg = ivget(initiator, :@message_queue).deq(true)

    # receive ping
    responder.add_message msg
    ping_packet = ivget(responder, :@packet_queue).deq(true)
    assert ping_packet.instance_of?(Packet)
    data = proto.class::Ping.decode_payload ping_packet.payload

    # reply with pong
    pong = proto.create_pong
    responder.add_packet pong
    msg = ivget(responder, :@message_queue).deq(true)

    # receive pong
    initiator.add_message msg
    pong_packet = ivget(initiator, :@packet_queue).deq(true)
    assert pong_packet.instance_of?(Packet)
    data = proto.class::Pong.decode_payload pong_packet.payload
  end

end
