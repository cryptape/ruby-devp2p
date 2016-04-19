# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ECIESTest < Minitest::Test
  include DEVp2p

  def test_kdf
    assert_equal "\xF0?\xB9/\xB7o\xCE\x8F\xD8\xB2\xD7\xE4\xD4\x8CFo;\xA1T\b\xDBg\xB4\t\x92\xC2-\nt\xE79'", Crypto::ECIES.kdf("\x01"*32, 32)
  end

end

