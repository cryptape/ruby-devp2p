# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Discovery

    class Node < Kademlia::Node

      def self.from_uri(uri)
        ip, port, pubkey = Utils.host_port_pubkey_from_uri(uri)
        new(pubkey, Address.new(ip, port.to_i))
      end

      attr_accessor :address

      def initialize(pubkey, address=nil)
        raise ArgumentError, 'invalid address' unless address.nil? || address.is_a?(Address)

        super(pubkey)

        self.address = address
        @reputation = 0
        @rlpx_version = 0
      end

      def to_uri
        Utils.host_port_pubkey_to_uri(address.ip, address.udp_port, pubkey)
      end

    end

  end
end
