# -*- encoding : ascii-8bit -*-

require 'secp256k1' # bitcoin-secp256k1

require 'devp2p/crypto/ecc_x'

module DEVp2p
  module Crypto

    extend self

    def mk_privkey(seed)
      Utils.keccak256 seed
    end

    def privtopub(privkey)
      priv = Secp256k1::PrivateKey.new privkey: privkey, raw: true

      pub = priv.pubkey.serialize(compressed: false)
      raise InvalidKeyError, 'invalid pubkey' unless pub.size == 65 && pub[0] == "\x04"

      pub[1,64]
    end

  end
end
