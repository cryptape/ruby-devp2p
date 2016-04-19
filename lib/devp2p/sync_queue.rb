# -*- encoding : ascii-8bit -*-

require 'thread'

##
# This is the synchronized queue implementation of ruby 2.0.0 with some
# extentions like #peek.
#
class SyncQueue

  def initialize
    @que = []
    @que.taint          # enable tainted communication
    @num_waiting = 0
    self.taint
    @mutex = Mutex.new
    @cond = ConditionVariable.new
  end

  def enq(obj)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      @mutex.synchronize do
        @que.push obj
        @cond.signal
      end
    end
  end
  alias << enq

  def deq(non_block=false)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      @mutex.synchronize do
        while true
          if @que.empty?
            if non_block
              raise ThreadError, "queue empty"
            else
              begin
                @num_waiting += 1
                @cond.wait @mutex
              ensure
                @num_waiting -= 1
              end
            end
          else
            return @que.shift
          end
        end
      end
    end
  end

  # Same as pop except it will not remove the element from queue, just peek.
  def peek(non_block=false)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      @mutex.synchronize do
        while true
          if @que.empty?
            if non_block
              raise ThreadError, "queue empty"
            else
              begin
                @num_waiting += 1
                @cond.wait @mutex
              ensure
                @num_waiting -= 1
              end
            end
          else
            return @que[0]
          end
        end
      end
    end
  end

  def empty?
    @que.empty?
  end

  def clear
    @que.clear
  end

  def length
    @que.length
  end
  alias size length

  # Returns the number of threads waiting on the queue.
  def num_waiting
    @num_waiting
  end
end
