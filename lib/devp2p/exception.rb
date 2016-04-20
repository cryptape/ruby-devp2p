# -*- encoding : ascii-8bit -*-

module DEVp2p

  class MissingRequiredServiceError < StandardError; end
  class InvalidCommandStructure < StandardError; end
  class DuplicatedCommand < StandardError; end
  class FrameError < StandardError; end
  class MultiplexerError < StandardError; end
  class RLPxSessionError < StandardError; end
  class MultiplexedSessionError < StandardError; end
  class AuthenticationError < StandardError; end
  class FormatError < StandardError; end
  class InvalidKeyError < StandardError; end
  class InvalidSignatureError < StandardError; end
  class InvalidMACError < StandardError; end
  class EncryptionError < StandardError; end
  class DecryptionError < StandardError; end
  class KademliaRoutingError < StandardError; end
  class KademliaNodeNotFound < StandardError; end

end
