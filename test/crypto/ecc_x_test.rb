# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ECCxTest < Minitest::Test
  include DEVp2p

  def setup
    @ecc = Crypto::ECCx.new
  end

  def test_generate_key
    privkey, pubkey = @ecc.generate_key
    assert_equal 32, privkey.size
    assert_equal 64, pubkey.size
    assert_equal Crypto.privtopub(privkey), pubkey
  end

  def test_valid_key
    privkey, pubkey = @ecc.generate_key
    assert_equal false, @ecc.valid_key?(pubkey, "\x01"*32)
    assert_equal true, @ecc.valid_key?(pubkey, privkey)
    assert_equal true, @ecc.valid_key?(pubkey)
  end

end
