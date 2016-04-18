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

  def test_get_ecdh_key
    ecc = Crypto::ECCx.new "\x01"*32 # local private key
    remote_pubkey = Crypto.privtopub "\x02"*32 # remote public key
    assert_equal "\xD0\x15\x8A8\xFA\xF6\x11\x8A\xF13\xAF\x12\xD9\xBF\xA3\x88\xEA\xB4\xA0\x8D\x1A \x88\xEAnn\xC1&\x9E\x03V\x7F", ecc.get_ecdh_key(remote_pubkey)
  end

end
