# -*- encoding : ascii-8bit -*-
require 'test_helper'

class QueueTest < Minitest::Test

  def test_peek
    q = SyncQueue.new
    t = Thread.new do
      timeout(2) { assert_equal 1, q.peek }
      timeout(2) { assert_equal 1, q.pop }
    end
    q.push 1
    t.join
  end

end
