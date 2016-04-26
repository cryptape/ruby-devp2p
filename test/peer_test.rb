# -*- encoding : ascii-8bit -*-
require 'test_helper'

class PeerTest < Minitest::Test
  include DEVp2p

  def test_handshake
    Logging.logger.root.level = :debug

    Celluloid.shutdown rescue nil
    Celluloid.boot

    a_app, b_app = get_connected_apps

    a_app.stop
    b_app.stop
  end

  private

  def get_connected_apps
    a_app = get_app 'a'
    b_app = get_app 'b'

    a_peermgr = a_app.services.peermanager
    b_peermgr = b_app.services.peermanager

    # connect
    b_config = get_config 'b'
    host = b_config[:p2p][:listen_host]
    port = b_config[:p2p][:listen_port]
    pubkey = Crypto.privtopub Utils.decode_hex(b_config[:node][:privkey_hex])
    a_peermgr.connect host, port, pubkey

    return a_app, b_app
  end

  def get_app(name)
    config = get_config name
    app = BaseApp.new config
    PeerManager.register_with_app app
    app.start
    app
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
