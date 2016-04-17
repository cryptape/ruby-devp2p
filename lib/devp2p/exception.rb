# -*- encoding : ascii-8bit -*-

module DEVp2p

  class MissingRequiredServiceError < StandardError; end
  class InvalidCommandStructure < StandardError; end
  class DuplicatedCommand < StandardError; end
  class FrameError < StandardError; end
  class MultiplexerError < StandardError; end
  class RLPxSessionError < StandardError; end
  class AuthenticationError < StandardError; end
  class FormatError < StandardError; end
  class InvalidKeyError < StandardError; end

end
