# -*- encoding : ascii-8bit -*-
require 'test_helper'

class SyncQueueTest < Minitest::Test

  class Actor
    include Celluloid

    attr :queue

    def initialize(max_size=nil)
      @queue = SyncQueue.new max_size
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

  def setup
    Celluloid.shutdown rescue nil
    Celluloid.boot
  end

  def test_enq_deq_raw
    a = Actor.new 2
    a.queue.enq 1
    a.queue.enq 2

    future = a.future.enq 3
    assert !future.ready?

    a.deq
    assert future.ready?

    future = a.future.enq 4
    assert !future.ready?

    a.deq
    a.deq
    a.deq

    future = a.future.deq
    assert !future.ready?

    a.enq 0
    assert future.ready?
    assert a.queue.empty?
  end

  def test_enq_deq
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
    a = Actor.new
    future = a.future.peek
    assert !future.ready?

    a.enq 1
    sleep 0.2
    assert future.ready?
    assert_equal 1, future.value
  end

end
