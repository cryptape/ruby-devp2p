# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ECCxTest < Minitest::Test
  include DEVp2p

  def test_generate_key
    privkey, pubkey = Crypto::ECCx.new.generate_key
    assert_equal 32, privkey.size
    assert_equal 64, pubkey.size
    assert_equal Crypto.privtopub(privkey), pubkey
  end

end
