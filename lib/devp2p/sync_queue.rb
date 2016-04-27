# -*- encoding : ascii-8bit -*-

##
# A naive synchronized queue for Celluloid actors.
#
class SyncQueue

  def initialize
    @queue = []
    @num_waiting = 0
    @cond = Celluloid::Condition.new
  end

  def enq(obj)
    @queue.push obj
    @cond.signal
  end
  alias << enq

  def deq(non_block=false)
    loop do
      if @queue.empty?
        if non_block
          raise ThreadError, 'queue empty'
        else
          begin
            @num_waiting += 1
            @cond.wait
          ensure
            @num_waiting -= 1
          end
        end
      else
        return @queue.shift
      end
    end
  end

  # Same as pop except it will not remove the element from queue, just peek.
  def peek(non_block=false)
    loop do
      if @queue.empty?
        if non_block
          raise ThreadError, 'queue empty'
        else
          begin
            @num_waiting += 1
            @cond.wait
          ensure
            @num_waiting -= 1
          end
        end
      else
        return @queue[0]
      end
    end
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
