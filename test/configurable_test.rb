# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ConfigurableTest < Minitest::Test

  class Mom
    extend ::DEVp2p::Configurable
    add_config(
      name: 'mother',
      gender: :female,
      parent: true
    )
  end

  class Son < Mom
    name 'son'
    gender :male
    parent false
  end

  class Daughter < Mom
    parent false
  end

  class Grandchild < Son

  end

  def test_subclass_config
    assert_equal 'mother', Mom.name
    assert_equal 'son', Son.name
    assert_equal 'mother', Daughter.name
    assert_equal 'son', Grandchild.name

    assert_equal :male, Son.gender
    assert_equal :female, Daughter.gender

    assert_equal true, Mom.parent
    assert_equal false, Son.parent
    assert_equal false, Daughter.parent
  end

  def test_instance_helpers
    assert_equal Mom.name, Mom.new.name
    assert_equal Mom.gender, Mom.new.gender
  end

end
