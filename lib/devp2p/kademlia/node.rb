# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Kademlia

    class Node

      attr :id, :pubkey
      attr_accessor :address

      def initialize(pubkey)
        raise ArgumentError, "invalid pubkey" unless pubkey.size == 64

        @id = Crypto.keccak256(pubkey)
        raise "invalid node id" unless @id.size * 8 == ID_SIZE

        @id = Utils.big_endian_to_int @id
        @pubkey = pubkey
      end

      def distance(other)
        id ^ other.id
      end

      def id_distance(_id)
        id ^ _id
      end

      def ==(other)
        other.instance_of?(self.class) && pubkey == other.pubkey
      end

      def to_s
        "<Node(#{Utils.encode_hex pubkey[0,8]})>"
      end
      alias inspect to_s
    end

  end
end
