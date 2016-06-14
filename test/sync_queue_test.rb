# -*- encoding : ascii-8bit -*-
require 'test_helper'

class SyncQueueTest < Minitest::Test

  class Actor
    include Concurrent::Async

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

  def test_enq_deq_raw
    a = Actor.new 2
    a.queue.enq 1
    a.queue.enq 2

    ivar = a.async.enq 3
    sleep 0.1
    assert ivar.pending?

    a.queue.deq
    sleep 0.1
    assert ivar.fulfilled?

    ivar = a.async.enq 4
    sleep 0.1
    assert ivar.pending?

    a.queue.deq
    a.queue.deq
    a.queue.deq

    ivar = a.async.deq
    sleep 0.1
    assert ivar.pending?

    a.queue.enq 0
    sleep 0.1
    assert ivar.fulfilled?
    assert a.queue.empty?
  end

  def test_enq_deq
    a = Actor.new
    ivar = a.async.add
    sleep 0.1
    assert ivar.pending?

    a.queue.enq 1
    sleep 0.1
    assert ivar.pending?

    a.queue.enq 2
    sleep 0.1
    assert ivar.fulfilled?
    assert_equal 3, ivar.value
  end

  def test_peek
    a = Actor.new
    ivar = a.async.peek
    sleep 0.1
    assert ivar.pending?

    a.queue.enq 1
    sleep 0.1
    assert ivar.fulfilled?
    assert_equal 1, ivar.value
  end

end
