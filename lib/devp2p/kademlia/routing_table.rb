# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Kademlia

    class RoutingTable

      def initialize(node)
        @node = node
        @buckets = [KBucket.new(0, MAX_NODE_ID)]
      end

      include Enumerable
      def each(&block)
        @buckets.each do |b|
          b.each(&block)
        end
      end

      def split_bucket(bucket)
        index = @buckets.index bucket
        @buckets[index..index] = bucket.split
      end

      def idle_buckets
        t_idle = Time.now - IDLE_BUCKET_REFRESH_INTERVAL
        @buckets.select {|b| b.last_updated < t_idle }
      end

      def not_full_buckets
        @buckets.select {|b| b.size < K }
      end

      def add(node)
        raise ArgumentError, 'cannot add self' if node == @node

        bucket = bucket_by_node node
        eviction_candidate = bucket.add_node node

        if eviction_candidate # bucket is full
          # split if the bucket has the local node in its range or if the depth
          # is not congruent to 0 mod B
          if bucket.in_range?(@node) || bucket.splitable?
            split_bucket bucket
            return add(node) # retry
          end

          # nothing added, ping eviction_candidate
          return eviction_candidate
        end

        nil # successfully added to not full bucket
      end

      def delete(node)
        bucket_by_node(node).delete node
      end

      def bucket_by_node(node)
        @buckets.each do |bucket|
          if node.id < bucket.right
            raise KademliaRoutingError, "mal-formed routing table" unless node.id >= bucket.left
            return bucket
          end
        end

        raise KademliaNodeNotFound
      end

      def buckets_by_id_distance(id)
        raise ArgumentError, 'id must be integer' unless id.is_a?(Integer)
        @buckets.sort_by {|b| b.id_distance(id) }
      end

      def include?(node)
        bucket_by_node(node).include?(node)
      end

      def size
        @buckets.map(&:size).reduce(0, &:+)
      end

      ##
      # sorting by bucket.midpoint does not work in edge cases, buld a short
      # list of `k * 2` nodes and sort and shorten it.
      #
      # TODO: can we do better?
      #
      def neighbours(node, k=K)
        raise ArgumentError, 'node must be Node or node id' unless node.instance_of?(Node) || node.is_a?(Integer)

        node = node.id if node.instance_of?(Node)

        nodes = []
        buckets_by_id_distance(node).each do |bucket|
          bucket.nodes_by_id_distance(node).each do |n|
            if n != node
              nodes.push n
              break if nodes.size == k * 2
            end
          end
        end

        nodes.sort_by {|n| n.id_distance(node) }[0,k]
      end

      ##
      # naive correct version simply compares all nodes
      #
      def neighbours_within_distance(id, distance)
        raise ArgumentError, 'invalid id' unless id.is_a?(Integer)

        select {|n| n.id_distance(id) <= distance }
          .sort_by {|n| n.id_distance(id) }
      end

    end

  end
end
