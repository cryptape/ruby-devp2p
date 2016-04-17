# -*- encoding : ascii-8bit -*-
require 'test_helper'

class UtilsTest < Minitest::Test
  include DEVp2p

  def test_keccak256
    assert_equal 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470', Utils.encode_hex(Utils.keccak256(''))
  end

  def test_sxor
    assert_equal 'PPP', Utils.sxor('abc', '123')
  end

  def test_update_config_with_defaults
    c = {a: {b: 1}, g: 5}
    d = {a: {b: 2, c: 3}, d: 4, e: {f: 1}}
    r = {a: {b: 1, c: 3}, d: 4, e: {f: 1}, g: 5}
    assert_equal r, Utils.update_config_with_defaults(c, d)

    c = {a: {b: 1}, g: 5, h: [], k: [2]}
    d = {a: {b: 2, c: 3}, d: 4, e: {f: 1, i: [1, 2]}, j: []}
    r = {a: {b: 1, c: 3}, d: 4, e: {f: 1, i: [1, 2]}, j: [], g: 5, h: [], k: [2]}
    assert_equal r, Utils.update_config_with_defaults(c, d)
  end

end
