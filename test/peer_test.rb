# -*- encoding : ascii-8bit -*-
require 'test_helper'

class PeerTest < Minitest::Test
  include DEVp2p

  def test_handshake
    a_app, b_app = get_connected_apps

    sleep 0.1
    a_app.stop
    b_app.stop
  end

  class ::DEVp2p::P2PProtocol
    class Transfer < ::DEVp2p::Command
      cmd_id 4
      structure(raw_data: RLP::Sedes.binary)

      def create(proto, raw_data='')
        [raw_data]
      end
    end
  end

  def test_big_transfer
    a_app, b_app = get_connected_apps
    sleep 0.1

    a_protocol = ivget(a_app.services.peermanager, :@peers)[0].protocols[P2PProtocol]
    b_protocol = ivget(b_app.services.peermanager, :@peers)[0].protocols[P2PProtocol]

    t = Time.now
    cb = ->(proto, **data) { puts "took #{Time.now - t}, data: #{data['raw_data']}" }

    b_protocol.receive_transfer_callbacks.push cb
    raw_data = '0' * 1000 * 1000
    a_protocol.send_transfer raw_data

    sleep 0.5
    a_app.stop
    sleep 0.5
    b_app.stop
    sleep 0.1
  end

  private

  def get_connected_apps
    a_app = get_app 'a'
    b_app = get_app 'b'

    a_peermgr = a_app.services.peermanager
    b_peermgr = b_app.services.peermanager
    sleep 0.1

    # connect
    b_config = get_config 'b'
    host = b_config[:p2p][:listen_host]
    port = b_config[:p2p][:listen_port]
    pubkey = Crypto.privtopub Utils.decode_hex(b_config[:node][:privkey_hex])
    a_peermgr.connect host, port, pubkey
    sleep 0.1

    return a_app, b_app
  end

  def get_app(name)
    config = get_config name
    app = App.new config
    PeerManager.register_with_app app
    app.start
    app
  rescue
    puts $!
    puts $!.backtrace[0,10].join("\n")
  end

  def get_config(name)
    { p2p: {
        listen_host: '127.0.0.1',
        listen_port: 3000 + name[0].ord
      },
      node: {
        privkey_hex: Utils.encode_hex(Crypto.keccak256(name))
      }
    }
  end

end
