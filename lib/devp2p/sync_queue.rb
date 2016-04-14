# -*- encoding : ascii-8bit -*-

require 'thread'

##
# This is the synchronized queue implementation of ruby 2.0.0 with some
# extentions like #peek.
#
class SyncQueue
  #
  # Creates a new queue.
  #
  def initialize
    @que = []
    @que.taint          # enable tainted communication
    @num_waiting = 0
    self.taint
    @mutex = Mutex.new
    @cond = ConditionVariable.new
  end

  #
  # Pushes +obj+ to the queue.
  #
  def push(obj)
    Thread.handle_interrupt(StandardError => :on_blocking) do
      @mutex.synchronize do
        @que.push obj
        @cond.signal
      end
    end
  end

  #
  # Alias of push
  #
  alias << push

  #
  # Alias of push
  #
  alias enq push

  #
  # Retrieves data from the queue.  If the queue is empty, the calling thread is
  # suspended until data is pushed onto the queue.  If +non_block+ is true, the
  # thread isn't suspended, and an exception is raised.
  #
  def pop(non_block=false)
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

  #
  # Alias of pop
  #
  alias shift pop

  #
  # Alias of pop
  #
  alias deq pop

  #
  # Same as pop except it will not remove the element from queue, just peek.
  #
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

  #
  # Returns +true+ if the queue is empty.
  #
  def empty?
    @que.empty?
  end

  #
  # Removes all objects from the queue.
  #
  def clear
    @que.clear
  end

  #
  # Returns the length of the queue.
  #
  def length
    @que.length
  end

  #
  # Alias of length.
  #
  alias size length

  #
  # Returns the number of threads waiting on the queue.
  #
  def num_waiting
    @num_waiting
  end
end
