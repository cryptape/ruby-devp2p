# -*- encoding : ascii-8bit -*-
require 'test_helper'

class PeerTest < Minitest::Test
  include DEVp2p

  def test_app_restart
    Celluloid.shutdown rescue nil
    Celluloid.boot

    host, port = '127.0.0.1', 3020

    a_config = {
      p2p: {
        listen_host: host,
        listen_port: port
      },
      node: {
        privkey_hex: Utils.encode_hex(Crypto.keccak256('a'))
      }
    }
    a_app = BaseApp.new a_config
    PeerManager.register_with_app(a_app)

    # Restart app 10-times: there should be no exception
    10.times do |i|
      sleep 0.1
      a_app.start
      assert !a_app.services.peermanager.stopped?

      sleep 0.1
      try_tcp_connect host, port
      sleep 0.1
      assert_equal 0, a_app.services.peermanager.num_peers

      sleep 0.1
      a_app.stop
      assert_equal nil, a_app.services.peermanager
    end

    # start the app 10-times: there should be no exception
    10.times do |i|
      a_app.start
      assert !a_app.services.peermanager.stopped?
      sleep 0.1
      try_tcp_connect host, port
    end

    sleep 0.1
    a_app.stop
    assert_equal nil, a_app.services.peermanager
  end

  private

  def try_tcp_connect(host, port)
    s = TCPSocket.new host, port
    s.close
  end

end
