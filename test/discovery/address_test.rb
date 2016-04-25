# -*- encoding : ascii-8bit -*-
require 'test_helper'

class DiscoveryAddressTest < Minitest::Test
  include DEVp2p::Discovery

  def test_address
    ipv4 = "127.98.19.21"
    ipv6 = '5aef:2b::8'
    hostname = 'localhost'
    port = 1

    a4 = Address.new ipv4, port
    aa4 = Address.new ipv4, port
    assert_equal aa4, a4

    a6 = Address.new ipv6, port
    aa6 = Address.new ipv6, port
    assert_equal aa6, a6

    b_a4 = a4.to_endpoint
    assert_equal a4, Address.from_endpoint(*b_a4)

    b_a6 = a6.to_endpoint
    assert_equal 3, b_a6.size
    assert_equal a6, Address.from_endpoint(*b_a6)

    assert_equal 16, b_a6[0].size
    assert_equal 4, b_a4[0].size
    assert b_a6[1].instance_of?(String)

    host_a = Address.new hostname, port
    assert_equal "127.0.0.1", host_a.ip
  end

end
