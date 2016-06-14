# -*- encoding : ascii-8bit -*-

require 'concurrent'
require 'block_logger'
require 'rlp'

module DEVp2p
  Logger = BlockLogger

  TT16 = 2**16
  TT256 = 2**256

  NODE_URI_SCHEME = 'enode://'.freeze
end

require 'devp2p/version'

require 'devp2p/exception'
require 'devp2p/crypto'
require 'devp2p/utils'
require 'devp2p/configurable'

require 'devp2p/app'
require 'devp2p/service'
require 'devp2p/wired_service'

require 'devp2p/sync_queue'
require 'devp2p/frame'
require 'devp2p/multiplexer'
require 'devp2p/multiplexed_session'

require 'devp2p/kademlia'
require 'devp2p/discovery'
require 'devp2p/connection_monitor'
require 'devp2p/command'
require 'devp2p/protocol'
require 'devp2p/p2p_protocol'
require 'devp2p/peer_manager'
require 'devp2p/peer_errors'
require 'devp2p/peer'
