# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ECCxTest < Minitest::Test
  include DEVp2p

  def test_generate_key
    privkey, pubkey = Crypto::ECCx.generate_key
    assert_equal 32, privkey.size
    assert_equal 64, pubkey.size
    assert_equal Crypto.privtopub(privkey), pubkey
  end

  def test_valid_key
    privkey, pubkey = Crypto::ECCx.generate_key
    assert_equal false, Crypto::ECCx.valid_key?(pubkey, "\x01"*32)
    assert_equal true, Crypto::ECCx.valid_key?(pubkey, privkey)
    assert_equal true, Crypto::ECCx.valid_key?(pubkey)
  end

  def test_get_ecdh_key
    ecc = Crypto::ECCx.new "\x01"*32 # local private key
    remote_pubkey = Crypto.privtopub "\x02"*32 # remote public key
    assert_equal "\xD0\x15\x8A8\xFA\xF6\x11\x8A\xF13\xAF\x12\xD9\xBF\xA3\x88\xEA\xB4\xA0\x8D\x1A \x88\xEAnn\xC1&\x9E\x03V\x7F", ecc.get_ecdh_key(remote_pubkey)
  end

  def test_get_ecdh_key2
    privkey = Utils.decode_hex "332143e9629eedff7d142d741f896258f5a1bfab54dab2121d3ec5000093d74b"
    remote_pubkey = Utils.decode_hex "f0d2b97981bd0d415a843b5dfe8ab77a30300daab3658c578f2340308a2da1a07f0821367332598b6aa4e180a41e92f4ebbae3518da847f0b1c0bbfe20bcf4e1"
    agree_expected = Utils.decode_hex "ee1418607c2fcfb57fda40380e885a707f49000a5dda056d828b7d9bd1f29a08"

    e = Crypto::ECCx.new privkey
    assert_equal agree_expected, e.get_ecdh_key(remote_pubkey)
  end

  def test_valid_ecc
    e = get_ecc
    assert_equal 64, e.raw_pubkey.size
    assert Crypto::ECCx.valid_key?(e.raw_pubkey)
    assert Crypto::ECCx.valid_key?(e.raw_pubkey, ivget(e, :@raw_privkey))

    pubkey = "\x00"*64
    assert !Crypto::ECCx.valid_key?(pubkey)
  end

  def test_asymetric
    bob = get_ecc 'secret2'

    pt = 'Hello Bob'
    ct = Crypto.encrypt pt, bob.raw_pubkey
    assert_equal pt, bob.decrypt(ct)
  end

  def test_signature
    bob = get_ecc 'secret2'

    # sign
    message = Crypto.keccak256 'Hello Alice'
    signature = bob.sign message

    assert_equal true, Crypto.verify(bob.raw_pubkey, signature, message)
    assert_equal true, Crypto::ECCx.new(nil, bob.raw_pubkey).verify(signature, message)
  end

  def test_recover
    alice = get_ecc 'secret1'
    message = Crypto.keccak256 'hello bob'
    signature = alice.sign message

    assert_equal 65, signature.size
    assert_equal true, Crypto.verify(alice.raw_pubkey, signature, message)

    recovered_pubkey = Crypto.ecdsa_recover(message, signature)
    assert_equal 64, recovered_pubkey.size
    assert_equal alice.raw_pubkey, recovered_pubkey
  end

  def test_en_decrypt
    alice = Crypto::ECCx.new
    bob = Crypto::ECCx.new
    msg = 'test'
    ct = alice.encrypt msg, bob.raw_pubkey
    assert_equal msg, bob.decrypt(ct)
  end

  def test_en_decrypt_shared_mac_data
    alice = Crypto::ECCx.new
    bob = Crypto::ECCx.new
    msg = 'test'
    shared_mac_data = 'shared mac data'
    ct = alice.encrypt(msg, bob.raw_pubkey, shared_mac_data)
    assert_equal msg, bob.decrypt(ct, shared_mac_data)

    assert_raises(DecryptionError) { bob.decrypt(ct, 'wrong') }
  end

  private

  def get_ecc(secret='')
    Crypto::ECCx.new Crypto.mk_privkey(secret)
  end

end
