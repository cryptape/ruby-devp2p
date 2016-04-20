# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Kademlia

    ##
    # Each k-bucket is kept sorted by time last seen - least-recently seen node
    # at the head, most-recently seen at the tail. For small values of i, the
    # k-buckets will generally be empty (as no appropriate nodes will exist).
    # For large values of i, the lists can grow up to size k, where k is a
    # system-wide replication parameter.
    #
    # k is chosen such that any given k nodes are very unlikely to fail within
    # an hour of each other (for example k = 20).
    #
    class KBucket

      attr :left, :right, :last_updated

      def initialize(left, right)
        @left, @right = left, right
        @nodes = []
        @replacement_cache = []
        @last_updated = Time.now
      end

      include Enumerable
      def each(&block)
        @nodes.each(&block)
      end

      ##
      # If the sending node already exists in the recipient's k-bucket, the
      # recipient moves it to the tail of the list.
      #
      # If the node is not already in the appropriate k-bucket and the bucket
      # has fewer than k entries, then the recipient just inserts the new
      # sender at the tail of the list.
      #
      # If the appropriate k-bucket is full, however, then the recipient pings
      # the k-bucket's least-recently seen node to decide what to do:
      #
      #   * on success: return nil
      #   * on bucket full: return least recently seen node for eviction check
      #
      def add(node)
        @last_updated = Time.now

        if include?(node) # already exists
          delete node
          @nodes.push node
          nil
        elsif size < K # add if fewer than k entries
          @nodes.push node
          nil
        else # bucket is full
          head
        end
      end

      def delete(node)
        return unless include?(node)
        @nodes.delete node
      end

      ##
      # least recently seen
      #
      def head
        @nodes.first
      end

      ##
      # last recently seen
      #
      def tail
        @nodes.last
      end

      def range
        [left, right]
      end

      def midpoint
        left + (right - left) / 2
      end

      def distance(node)
        midpoint ^ node.id
      end

      def id_distance(id)
        midpoint ^ id
      end

      def nodes_by_id_distance(id)
        raise ArgumentError, 'invalid id' unless id.is_a?(Integer)
        @nodes.sort_by {|n| n.id_distance(id) }
      end

      def should_split?
        full? && splitable?
      end

      def splitable?
        d = depth
        d % B != 0 && d != ID_SIZE
      end

      ##
      # split at the median id
      #
      def split
        split_id = midpoint

        lower = self.class.new left, split_id
        upper = self.class.new split_id + 1, right

        # distribute nodes
        @nodes.each do |node|
          bucket = node.id <= split_id ? lower : upper
          bucket.add_node node
        end

        # distribute replacement nodes
        @replacement_cache.each do |node|
          bucket = node.id <= split_id ? lower : upper
          bucket.add_replacement_node node
        end

        return lower, upper
      end

      ##
      # depth is the prefix shared by all nodes in bucket. i.e. the number of
      # shared leading bits.
      #
      def depth
        return ID_SIZE if size < 2

        bits = @nodes.map {|n| Utils.bpad(n.id, ID_SIZE) }
        ID_SIZE.times do |i|
          if bits.map {|b| b[0,i] }.uniq.size != 1
            return i - 1
          end
        end

        raise "should never be here"
      end

      def in_range?(node)
        left <= node.id && node.id <= right
      end

      def full?
        size == K
      end

      def size
        @nodes.size
      end

      def include?(node)
        @nodes.include?(node)
      end

    end

  end
end
