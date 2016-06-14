# -*- encoding : ascii-8bit -*-

require 'securerandom'

module DEVp2p
  module Crypto
    class ECCx

      CURVE = 'secp256k1'.freeze

      class <<self
        def valid_key?(raw_pubkey, raw_privkey=nil)
          return false unless raw_pubkey.size == 64

          group = OpenSSL::PKey::EC::Group.new CURVE
          bn = OpenSSL::BN.new Utils.encode_hex("\x04#{raw_pubkey}"), 16
          point = OpenSSL::PKey::EC::Point.new group, bn

          key = OpenSSL::PKey::EC.new(CURVE)
          key.public_key = point
          key.private_key = OpenSSL::BN.new Utils.big_endian_to_int(raw_privkey) if raw_privkey
          key.check_key

          true
        rescue
          false
        end

        def generate_key
          curve = OpenSSL::PKey::EC.new(CURVE)
          curve.generate_key

          raw_privkey = Utils.zpad Utils.int_to_big_endian(curve.private_key.to_i), 32
          raw_pubkey = Utils.int_to_big_endian(curve.public_key.to_bn.to_i)
          raise InvalidKeyError, 'invalid pubkey' unless raw_pubkey.size == 65 && raw_pubkey[0] == "\x04"

          [raw_privkey, raw_pubkey[1,64]]
        end

        ##
        # Compute public key with the local private key and returns a 256bits
        # shared key
        #
        def get_ecdh_key(curve, raw_pubkey)
          pubkey = raw_pubkey_to_openssl_pubkey raw_pubkey
          curve.dh_compute_key pubkey
        end

        def raw_pubkey_to_openssl_pubkey(raw_pubkey)
          return unless raw_pubkey

          bn = OpenSSL::BN.new Utils.encode_hex("\x04#{raw_pubkey}"), 16
          group = OpenSSL::PKey::EC::Group.new CURVE
          OpenSSL::PKey::EC::Point.new group, bn
        end

        def raw_privkey_to_openssl_privkey(raw_privkey)
          return unless raw_privkey

          OpenSSL::BN.new Utils.big_endian_to_int(raw_privkey)
        end
      end

      attr :raw_pubkey

      def initialize(raw_privkey=nil, raw_pubkey=nil)
        if raw_privkey && raw_pubkey
          raise ArgumentError, 'must not provide pubkey with privkey'
        elsif raw_privkey
          raw_pubkey = Crypto.privtopub raw_privkey
        elsif raw_pubkey
          raise ArgumentError, 'invalid pubkey length' unless raw_pubkey.size == 64
        else
          raw_privkey, raw_pubkey = self.class.generate_key
        end

        if self.class.valid_key?(raw_pubkey, raw_privkey)
          @raw_pubkey, @raw_privkey = raw_pubkey, raw_privkey
          @pubkey_x, @pubkey_y = decode_pubkey raw_pubkey
          set_curve
        else
          @raw_pubkey, @raw_privkey = nil, nil
          @pubkey_x, @pubkey_y = nil, nil
          raise InvalidKeyError, "bad ECC keys"
        end
      end

      def sign(data)
        sig = Crypto.ecdsa_sign data, @raw_privkey
        raise InvalidSignatureError unless sig.size == 65
        sig
      end

      def verify(sig, msg)
        raise ArgumentError, 'invalid signature length' unless sig.size == 65
        Crypto.ecdsa_verify @raw_pubkey, sig, msg
      end

      def get_ecdh_key(raw_pubkey)
        self.class.get_ecdh_key curve, raw_pubkey
      end

      def ecies_encrypt(*args)
        ECIES.encrypt *args
      end
      alias encrypt ecies_encrypt

      def ecies_decrypt(*args)
        ECIES.decrypt curve, *args
      end
      alias decrypt ecies_decrypt

      def curve
        @curve ||= OpenSSL::PKey::EC.new(CURVE)
      end

      private

      def decode_pubkey(raw_pubkey)
        return [nil, nil] unless raw_pubkey

        raise ArgumentError, 'invalid pubkey length' unless raw_pubkey.size == 64
        [raw_pubkey[0,32], raw_pubkey[32,32]]
      end

      def set_curve
        curve.public_key = self.class.raw_pubkey_to_openssl_pubkey(@raw_pubkey)
        curve.private_key = self.class.raw_privkey_to_openssl_privkey(@raw_privkey)
      end

    end
  end
end
