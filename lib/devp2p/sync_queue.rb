# -*- encoding : ascii-8bit -*-

require 'thread'

class SyncQueue

  attr :queue, :max_size

  def initialize(max_size=nil)
    @queue = []
    @num_waiting = 0

    @max_size = max_size

    @mutex = Mutex.new
    @cond_full = ConditionVariable.new
    @cond_empty = ConditionVariable.new
  end

  def enq(obj, non_block=false)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      loop do
        @mutex.synchronize do
          if full?
            if non_block
              raise ThreadError, 'queue full'
            else
              begin
                @num_waiting += 1
                @cond_full.wait @mutex
              ensure
                @num_waiting -= 1
              end
            end
          else
            @queue.push obj
            @cond_empty.signal
            return obj
          end
        end
      end
    end
  end
  alias << enq

  def deq(non_block=false)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      loop do
        @mutex.synchronize do
          if empty?
            if non_block
              raise ThreadError, 'queue empty'
            else
              begin
                @num_waiting += 1
                @cond_empty.wait @mutex
              ensure
                @num_waiting -= 1
              end
            end
          else
            obj = @queue.shift
            @cond_full.signal
            return obj
          end
        end
      end
    end
  end

  # Same as pop except it will not remove the element from queue, just peek.
  def peek(non_block=false)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      loop do
        @mutex.synchronize do
          if empty?
            if non_block
              raise ThreadError, 'queue empty'
            else
              begin
                @num_waiting += 1
                @cond_empty.wait @mutex
              ensure
                @num_waiting -= 1
              end
            end
          else
            return @queue[0]
          end
        end
      end
    end
  end

  def full?
    @max_size && @queue.size >= @max_size
  end

  def empty?
    @queue.empty?
  end

  def clear
    @queue.clear
  end

  def length
    @queue.length
  end
  alias size length

  # Returns the number of threads waiting on the queue.
  def num_waiting
    @num_waiting
  end
end
