# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ConfigurableTest < Minitest::Test

  class Mom
    extend ::DEVp2p::Configurable
    add_config(
      gender: :female,
      parent: true
    )
  end

  class Son < Mom
    gender :male
    parent false
  end

  class Daughter < Mom
    parent false
  end

  def test_subclass_config
    assert_equal :male, Son.gender
    assert_equal :female, Daughter.gender

    assert_equal true, Mom.parent
    assert_equal false, Son.parent
    assert_equal false, Daughter.parent
  end

end
