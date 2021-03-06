# -*- encoding : ascii-8bit -*-
require 'test_helper'

class CryptoTest < Minitest::Test
  include DEVp2p

  def test_privtopub
    assert_equal "\e\x84\xC5V{\x12d@\x99]>\xD5\xAA\xBA\x05e\xD7\x1E\x184`H\x19\xFF\x9C\x17\xF5\xE9\xD5\xDD\a\x8Fp\xBE\xAF\x8FX\x8BT\x15\a\xFE\xD6\xA6B\xC5\xABB\xDF\xDF\x81 \xA7\xF69\xDEQ\"\xD4zi\xA8\xE8\xD1", Crypto.privtopub("\x01"*32)
  end

  def test_privtopub2
    priv = Crypto.mk_privkey 'test'
    pub = Crypto.privtopub priv
    pub2 = Crypto::ECCx.new(priv).raw_pubkey
    assert_equal pub, pub2
  end

  def test_keccak256
    assert_equal 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470', Utils.encode_hex(Crypto.keccak256(''))
  end

  def test_hmac_sha256
    assert_equal "rQ\xB8\xD0\xA5@\x88Q$\xD9\x7F'\xC5\xFC[\x84}\x87E6!\xF4#\xE7+\x9D\xE2\xA2\xE6\xE0\x00^", Crypto.hmac_sha256("\x01"*32, 'ether')

    k_mac = Utils.decode_hex("07a4b6dfa06369a570f2dcba2f11a18f")
    indata = Utils.decode_hex("4dcb92ed4fc67fe86832")
    expected = Utils.decode_hex("c90b62b1a673b47df8e395e671a68bfa68070d6e2ef039598bb829398b89b9a9")
    hmac = Crypto.hmac_sha256(k_mac, indata)
    assert_equal expected, hmac
  end

  def test_ecdsa_sign
    assert_equal "R\x90\xB9\xF6r/M\x1A\xAB\x99\xF0\"\xF8\xD6\xF1\xFA\xE6\x83\x00C9\x153\xA8L;\x127\xD3\xBD\x8DWP\xDD%\x06\xCD\x04o\xEBD_\xDD8\xAF\xEF\x9D\x7F\xB6\xEE\x18/R\xDCE*\t1\xCEHcz\xCC\xC6\x00", Crypto.ecdsa_sign("1"*32, "\x01"*32)
  end

  def test_recover
    alice = Crypto::ECCx.new Crypto.mk_privkey('secret1')
    message = (0...1024).map { SecureRandom.random_number(256).chr }.join
    message = Crypto.keccak256 message
    signature = alice.sign message

    recovered_pubkey = Crypto.ecdsa_recover message, signature
    assert_equal alice.raw_pubkey, recovered_pubkey
  end

end
