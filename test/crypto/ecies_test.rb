# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ECIESTest < Minitest::Test
  include DEVp2p

  def test_kdf
    assert_equal "\xF0?\xB9/\xB7o\xCE\x8F\xD8\xB2\xD7\xE4\xD4\x8CFo;\xA1T\b\xDBg\xB4\t\x92\xC2-\nt\xE79'", Crypto::ECIES.kdf("\x01"*32, 32)

    input1 = Utils.decode_hex "0de72f1223915fa8b8bf45dffef67aef8d89792d116eb61c9a1eb02c422a4663"
    expect1 = Utils.decode_hex "1d0c446f9899a3426f2b89a8cb75c14b"
    test1 = Crypto::ECIES.kdf(input1, 16)
    assert_equal expect1, test1

    input2 = Utils.decode_hex "961c065873443014e0371f1ed656c586c6730bf927415757f389d92acf8268df"
    expect2 = Utils.decode_hex "4050c52e6d9c08755e5a818ac66fabe478b825b1836fd5efc4d44e40d04dabcc"
    test2 = Crypto::ECIES.kdf(input2, 32)
    assert_equal expect2, test2
  end

  def test_ecies_enc
    bob = Crypto::ECCx.new
    msg = 'test yeah'
    ct = Crypto::ECIES.encrypt msg, bob.raw_pubkey
    msg2 = bob.ecies_decrypt ct
    assert_equal msg, msg2
  end

  def test_decrypt
    kmK = Utils.decode_hex "57baf2c62005ddec64c357d96183ebc90bf9100583280e848aa31d683cad73cb"
    kmCipher = Utils.decode_hex "04ff2c874d0a47917c84eea0b2a4141ca95233720b5c70f81a8415bae1dc7b746b61df7558811c1d6054333907333ef9bb0cc2fbf8b34abb9730d14e0140f4553f4b15d705120af46cf653a1dc5b95b312cf8444714f95a4f7a0425b67fc064d18f4d0a528761565ca02d97faffdac23de10"
    kmExpected = "a"
    kmPlain = Crypto::ECCx.new(kmK).ecies_decrypt(kmCipher)
    assert_equal kmExpected, kmPlain
  end

end

