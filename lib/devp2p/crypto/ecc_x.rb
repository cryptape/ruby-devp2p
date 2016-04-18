# -*- encoding : ascii-8bit -*-

require 'securerandom'

module DEVp2p
  module Crypto
    class ECCx

      CURVE = 'secp256k1'.freeze

      attr :raw_pubkey

      def initialize(raw_privkey=nil, raw_pubkey=nil)
        if raw_privkey && raw_pubkey
          raise ArgumentError, 'must not provide pubkey with privkey'
        elsif raw_privkey
          raw_pubkey = Crypto.privtopub raw_privkey
        elsif raw_pubkey
          # do nothing
        else
          raw_privkey, raw_pubkey = generate_key
        end

        if valid_key?(raw_pubkey, raw_privkey)
          @raw_pubkey, @raw_privkey = raw_pubkey, raw_privkey
          @pubkey_x, @pubkey_y = decode_pubkey raw_pubkey
        else
          @raw_pubkey, @raw_privkey = nil, nil
          @pubkey_x, @pubkey_y = nil, nil
          raise InvalidKeyError, "bad ECC keys"
        end
      end

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
        curve.generate_key

        raw_privkey = Utils.zpad Utils.int_to_big_endian(curve.private_key.to_i), 32
        raw_pubkey = Utils.int_to_big_endian(curve.public_key.to_bn.to_i)
        raise InvalidKeyError, 'invalid pubkey' unless raw_pubkey.size == 65 && raw_pubkey[0] == "\x04"

        [raw_privkey, raw_pubkey[1,64]]
      end

      def curve
        @curve ||= OpenSSL::PKey::EC.new(CURVE)
      end

      private

      def init(raw_pubkey, raw_privkey)
        if raw_pubkey
        else
          @private_key, @public_key = generate_key
        end
      end

      def decode_pubkey(raw_pubkey)
        return [nil, nil] unless raw_pubkey

        raise ArgumentError, 'invalid pubkey length' unless raw_pubkey.size == 64
        [raw_pubkey[0,32], raw_pubkey[32,32]]
      end


    end
  end
end
