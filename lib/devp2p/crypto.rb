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

    def hmac_sha256(key, msg)
      OpenSSL::HMAC.digest 'sha256', key, msg
    end

    def ecdsa_sign(msghash, privkey)
      raise ArgumentError, 'msghash length must be 32' unless msghash.size == 32

      priv = Secp256k1::PrivateKey.new privkey: privkey, raw: true
      sig = priv.ecdsa_recoverable_serialize priv.ecdsa_sign_recoverable(msghash, raw: true)
      "#{sig[0]}#{sig[1].chr}"
    end

    def ecdsa_recover(msghash, sig)
      raise ArgumentError, 'msghash length must be 32' unless msghash.size == 32
      raise ArgumentError, 'signature length must be 65' unless sig.size == 65

      pub = Secp256k1::PublicKey.new flags: Secp256k1::ALL_FLAGS
      recsig = pub.ecdsa_recoverable_deserialize sig[0,64], sig[64].ord
      pub.public_key = pub.ecdsa_recover msghash, recsig, raw: true
      pub.serialize(compressed: false)[1..-1]
    end

  end
end
