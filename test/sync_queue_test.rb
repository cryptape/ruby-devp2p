# -*- encoding : ascii-8bit -*-
require 'test_helper'

class SyncQueueTest < Minitest::Test

  class Actor
    include Celluloid

    def initialize
      @queue = SyncQueue.new
    end

    def enq(x)
      @queue.enq x
    end

    def deq
      @queue.deq
    end

    def add
      a = deq
      b = deq
      a + b
    end

    def peek
      @queue.peek
    end

  end

  def test_enq_deq
    Celluloid.shutdown rescue nil
    Celluloid.boot

    a = Actor.new
    future = a.future.add
    assert !future.ready?

    a.enq 1
    assert !future.ready?

    a.enq 2
    sleep 0.1
    assert future.ready?
    assert_equal 3, future.value
  end

  def test_peek
    Celluloid.shutdown rescue nil
    Celluloid.boot

    a = Actor.new
    future = a.future.peek
    assert !future.ready?

    a.enq 1
    sleep 0.2
    assert future.ready?
    assert_equal 1, future.value
  end

end
