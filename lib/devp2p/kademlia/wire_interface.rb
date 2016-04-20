# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Kademlia

    ##
    # defines the methods used by KademliaProtocol
    #
    class WireInterface

      def send_ping(node)
        raise NotImplementedError
      end

      def send_pong(node, id)
        raise NotImplementedError
      end

      def send_find_node(nodeid)
        raise NotImplementedError
      end

      def send_neighbours(node, neighbours)
        raise NotImplementedError
      end

    end

  end
end
