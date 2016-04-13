# -*- encoding : ascii-8bit -*-

require 'block_logger'

module DEVp2p
  Logger = BlockLogger
end

require 'devp2p/version'

require 'devp2p/base_service'
require 'devp2p/wired_service'

require 'devp2p/base_app'

