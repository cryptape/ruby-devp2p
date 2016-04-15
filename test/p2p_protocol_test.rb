# -*- encoding : ascii-8bit -*-
require 'test_helper'

class P2PProtocolTest < Minitest::Test
  include DEVp2p

  class PeerMock
    attr :packets, :config, :capabilities, :stopped, :hello_received, :remote_client_version, :remote_pubkey, :remote_hello_version

    def initialize
      @packets = []
      @config = Hashie::Mash.new(
        p2p: {listen_port: 3000},
        node: { id: "\x00"*64 },
        client_version_string: "devp2p 0.0.0"
      )
      @capabilities = [['p2p', 2], ['eth', 57]]
      @stopped = false
      @hello_received = false
      @remote_client_version = ''
      @remote_pubkey = ''
      @remote_hello_version = 0
    end

    def receive_hello(proto, kwargs)
      kwargs = Hashie.symbolize_keys kwargs
      required = %i(version client_version_string capabilities listen_port remote_pubkey)
      raise ArgumentError, "you must provide #{required}" unless required.all? {|k| kwargs.has_key?(k) }

      version = kwargs[:version]
      client_version_string = kwargs[:client_version_string]
      capabilities = kwargs[:capabilities]
      listen_port = kwargs[:listen_port]
      remote_pubkey = kwargs[:remote_pubkey]

      capabilities.each do |(name, ver)|
        raise ArgumentError, 'capability name must be string' unless name.instance_of?(String)
        raise ArgumentError, 'capability version must be integer' unless ver.is_a?(Integer)
      end

      @hello_received = true
      @remote_client_version = client_version_string
      @remote_pubkey = remote_pubkey
      @remote_hello_version = version
    end

    def send_packet(packet)
      @packets.push packet
    end

    def stop
      @stopped = true
    end
  end

  def test_eip8_hello
    Celluloid.shutdown rescue nil
    Celluloid.boot

    eip8_hello = Utils.decode_hex 'f87137916b6e6574682f76302e39312f706c616e39cdc5836574683dc6846d6f726b1682270fb840fda1cff674c90c9a197539fe3dfb53086ace64f83ed7c6eabec741f7f381cc803e52ab2cd55d5569bce4347107a310dfd5f88a010cd2ffd1005ca406f1842877c883666f6f836261720304'

    peer = PeerMock.new
    proto = P2PProtocol.new peer, WiredService.new(BaseApp.new)
    test_packet = Packet.new 0, 1, eip8_hello

    proto.receive_hello test_packet
    assert_equal true, peer.hello_received
  end

end
