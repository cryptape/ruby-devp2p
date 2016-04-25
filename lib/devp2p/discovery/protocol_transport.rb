# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Discovery

    module ProtocolTransport

      def send_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.is_a?(Address)
      end

      def receive_message(address, message)
        raise ArgumentError, 'address must be Address' unless address.is_a?(Address)
      end

    end

  end
end
