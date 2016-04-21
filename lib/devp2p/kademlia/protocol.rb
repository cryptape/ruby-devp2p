# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Kademlia

    class Protocol

      attr :node, :wire, :routing

      def initialize(node, wire)
        raise ArgumentError, 'node must be Node' unless node.is_a?(Node)
        raise ArgumentError, 'wire must be WireInterface' unless wire.is_a?(WireInterface)

        @node = node
        @wire = wire

        @routing = RoutingTable.new node

        @expected_pongs = {} # pingid => [timeout, node, replacement_node]
        @find_requests = {}  # nodeid => timeout
        @deleted_pingids = {}
      end

      def bootstrap(nodes)
        nodes.each do |node|
          next if node == @node

          @routing.add node
          find_node @node.id, node # add self to boot node's routing table
        end
      end

      ##
      # When a Kademlia node receives any message (request or reply) from
      # another node, it updates the appropriate k-bucket for the sender's node
      # ID.
      #
      # If the sending node already exists in the recipient's k-bucket, the
      # recipient moves it to the tail of the list.
      #
      # If the node is not already in the appropriate k-bucket and the bucket
      # has fewer than k entries, then the recipient just inserts the new
      # sender at the tail of the list.
      #
      # If the appropriate k-bucket is full, however, then the recipient pings
      # the k-bucket's least-recently seen node to decide what to do.
      #
      # If the least-recently seen node fails to respond, it is evicted from
      # the k-bucket and the new sender inserted at the tail.
      #
      # Otherwise, if the least-recently seen node responds, it is moved to the
      # tail of the list, and the new sender's contact is discarded.
      #
      # k-buckets effectively implement a least-recently seen eviction policy,
      # except the live nodes are never removed from the list.
      #
      def update(node, pingid=nil)
        raise ArgumentError, 'node must be Node' unless node.is_a?(Node)

        if node == @node
          logger.debug 'node is self', remoteid: node
          return
        end

        if pingid && !@expected_pongs.has_key?(pingid)
          pong_nodes = @expected_pongs.values.map {|v| v[1] }.uniq
          logger.debug "surprising pong", remoteid: node, expected: pong_nodes, pingid: Utils.encode_hex(pingid)[0,8]

          if @deleted_pingids.has_key?(pingid)
            logger.debug "surprising pong was deleted"
          else
            @expected_pongs.each_key do |key|
              if key =~ /#{node.pubkey}\z/
                logger.debug "waiting for ping from node, but echo mismatch", node: node, expected_echo: Utils.encode_hex(key[0,8]), received_echo: Utils.encode_hex(pingid[0,8])
              end
            end
          end

          return
        end

        # check for timed out pings and eventually evict them
        @expected_pongs.each do |_pingid, (timeout, _node, replacement)|
          if Time.now > timeout
            logger.debug "deleting timeout node", remoteid: _node, pingid: Utils.encode_hex(_pingid)[0,8]

            @deleted_pingids[_pingid] = true
            @expected_pongs.delete _pingid

            @routing.delete _node

            if replacement
              logger.debug "adding replacement", remoteid: replacement
              update replacement
              return
            end

            # prevent node from being added later
            return if _node == node
          end
        end

        # if we had registered this node for eviction test
        if @expected_pongs.has_key?(pingid)
          timeout, _node, replacement = @expected_pongs[pingid]
          logger.debug "received expected pong", remoteid: node

          if replacement
            logger.debug "adding replacement to cache", remoteid: replacement
            @routing.bucket_by_node(replacement).add_replacement(replacement)
          end

          @expected_pongs.delete pingid
        end

        # add node
        eviction_candidate = @routing.add node
        if eviction_candidate
          logger.debug "could not add", remoteid: node, pinging: eviction_candidate
          ping eviction_candidate, node
        else
          logger.debug "added", remoteid: node
        end

        # check idle buckets
        # idle bucket refresh:
        # for each bucket which hasn't been touched in 3600 seconds
        #   pick a random value in the range of the bucket and perform
        #   discovery for that value
        @routing.idle_buckets.each do |bucket|
          rid = SecureRandom.random_number bucket.left, bucket.right+1
          find_node rid
        end

        # check and removed timeout find requests
        @find_requests.keys.each do |nodeid|
          timeout = @find_requests[nodeid]
          @find_requests.delete(nodeid) if Time.now > timeout
        end

        logger.debug "updated", num_nodes: @routing.size, num_buckets: @routing.buckets_count
      end

      # FIXME: amplification attack (need to ping pong ping pong first)
      def find_node(targetid, via_node=nil)
        raise ArgumentError, 'targetid must be Integer' unless targetid.is_a?(Integer)
        raise ArgumentError, 'via_node must be nil or Node' unless via_node.nil? || via_node.is_a?(Node)

        @find_requests[targetid] = Time.now + REQUEST_TIMEOUT

        if via_node
          @wire.send_find_node via_node, targetid
        else
          query_neighbours targetid
        end

        # FIXME: should we return the closest node (allow callbacks on find_request)
      end

      ##
      # successful pings should lead to an update
      # if bucket is not full
      # elsif least recently seen, does ont respond in time
      #
      def ping(node, replacement=nil)
        raise ArgumentError, 'node must be Node' unless node.is_a?(Node)
        raise ArgumentError, 'cannot ping self' if node == @node
        logger.debug "pinging", remote: node, local: @node

        echoed = @wire.send_ping node
        pingid = mkpingid echoed, node
        timeout = Time.now + REQUEST_TIMEOUT
        logger.debug "set wait for pong from", remote: node, local: @node, pingid: Utils.encode_hex(pingid)[0,8]

        @expected_pongs[pingid] = [timeout, node, replacement]
      end

      ##
      # udp addresses determined by socket address of received Ping packets # ok
      # tcp addresses determined by contents of Ping packet # not yet
      def recv_ping(remote, echo)
        raise ArgumentError, 'remote must be Node' unless remote.is_a?(Node)
        logger.debug "recv ping", remote: remote, local: @node

        if remote == @node
          logger.warn "recv ping from self?!"
          return
        end

        update remote
        @wire.send_pong remote, echo
      end

      ##
      # tcp addresses are only updated upon receipt of Pong packet
      #
      def recv_pong(remote, echoed)
        raise ArgumentError, 'remote must be Node' unless remote.is_a?(Node)
        raise ArgumentError, 'cannot pong self' if remote == @node

        pingid = mkpingid echoed, remote
        logger.debug 'recv pong', remote: remote, pingid: Utils.encode_hex(pingid)[0,8], local: @node

        # FIXME: but neighbours will NEVER include remote
        #neighbours = @routing.neighbours remote
        #if !neighbours.empty? && neighbours[0] == remote
        #  neighbours[0].address = remote.address # update tcp address
        #end

        update remote, pingid
      end

      ##
      # if one of the neighbours is closer than the closest known neighbours
      #   if not timed out
      #     query closest node for neighbours
      # add all nodes to the list
      #
      def recv_neighbours(remote, neighbours)
        logger.debug "recv neighbours", remoteid: remote, num: neighbours.size, local: @node, neighbours: neighbours

        neighbours = neighbours.select {|n| n != @node && !@routing.include?(n) }

        # FIXME: we don't map requests to responses, thus forwarding to all
        @find_requests.each do |nodeid, timeout|
          closest = neighbours.sort_by {|n| n.id_distance(nodeid) }

          if Time.now < timeout
            closest_known = @routing.neighbours(nodeid)[0]
            raise KademliaRoutingError if closest_known == @node

            # send find_node requests to A closests
            closest[0, A].each do |close_node|
              if !closest_known || close_node.id_distance(nodeid) < closest_known.id_distance(nodeid)
                logger.debug "forwarding find request", closest: close_node, closest_known: closest_known
                @wire.send_find_node close_node, nodeid
              end
            end
          end
        end

        # add all nodes to the list
        neighbours.each do |node|
          ping node if node != @node
        end
      end

      # FIXME: amplification attack (need to ping pong ping pong first)
      def recv_find_node(remote, targetid)
        raise ArgumentError, 'remote must be Node' unless remote.is_a?(Node)

        update remote

        found = @routing.neighbours(targetid)
        logger.debug "recv find_node", remoteid: remote, found: found.size

        @wire.send_neighbours remote, found
      end

      private

      def logger
        @logger ||= Logger.new 'p2p.discovery.kademlia'
      end

      def query_neighbours(targetid)
        @routing.neighbours(targetid)[0, A].each do |n|
          @wire.send_find_node n, targetid
        end
      end

      def mkpingid(echoed, node)
        raise ArgumentError, 'node has no pubkey' if node.pubkey.nil? || node.pubkey.empty?

        pid = echoed + node.pubkey
        logger.debug "mkpingid", echoed: Utils.encode_hex(echoed), node: Utils.encode_hex(node.pubkey)

        pid
      end

    end

  end
end
