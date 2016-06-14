# -*- encoding : ascii-8bit -*-

require 'block_logger'
require 'rlp'

module DEVp2p
  Logger = BlockLogger

  TT16 = 2**16
  TT256 = 2**256

  NODE_URI_SCHEME = 'enode://'.freeze
end

require 'devp2p/version'
require 'devp2p/app'
