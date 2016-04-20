# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # Node discovery and network formation are implemented via a Kademlia-like
  # protocol. The major differences are that packets are signed, node ids are
  # the public keys, and DHT-related features are excluded. The FIND_VALUE and
  # STORE packets are not implemented.
  #
  # The parameters necessary to implement the protocol are:
  #
  #   * bucket size of 16 (denoted k in Kademlia)
  #   * concurrency of 3 (denoted alpha)
  #   * 8 bits per hop (denoted b) for routing
  #   * The eviction check interval is 75 milliseconds
  #   * request timeouts are 300ms
  #   * idle bucket-refresh interval is 3600 seconds
  #
  # Aside from the previously described exclusions, node discovery closely
  # follows system and protocol described by Maymounkov and Mazieres.
  #
  module Kademlia
    B = 8                               # bits per hop for routing
    K = 16                              # bucket size
    A = 3                               # alpha, parallel find node lookups

    REQUEST_TIMEOUT = 3 * 300 / 1000.0  # timeout of message round trips
    IDLE_BUCKET_REFRESH_INTERVAL = 3600 # ping all nodes in bucket if bucket was idle
    PUBKEY_SIZE = 512
    ID_SIZE = 256
    MAX_NODE_ID = 2 ** ID_SIZE - 1
  end

  require 'devp2p/kademlia/node'
  require 'devp2p/kademlia/k_bucket'
  require 'devp2p/kademlia/routing_table'

end
