# -*- encoding : ascii-8bit -*-

module DEVp2p

  class MissingRequiredServiceError < StandardError; end
  class InvalidCommandStructure < StandardError; end
  class DuplicatedCommand < StandardError; end
  class FrameError <  StandardError; end
  class MultiplexerError < StandardError; end

end
