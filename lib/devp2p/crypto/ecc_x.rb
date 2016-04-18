# -*- encoding : ascii-8bit -*-

require 'securerandom'

module DEVp2p
  module Crypto
    class ECCx

      CURVE = 'secp256k1'.freeze
      CIPHER = 'AES-128-CTR'.freeze
      CIPHER_BLOCK_SIZE = 16 # 128 / 8

      ECIES_ENCRYPT_OVERHEAD_LENGTH = 113

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
          set_curve
        else
          @raw_pubkey, @raw_privkey = nil, nil
          @pubkey_x, @pubkey_y = nil, nil
          raise InvalidKeyError, "bad ECC keys"
        end
      end

      ##
      # Compute public key with the local private key and returns a 256bits
      # shared key
      #
      def get_ecdh_key(raw_pubkey)
        pubkey = raw_pubkey_to_openssl_pubkey raw_pubkey
        curve.dh_compute_key pubkey
      end

      def sign(data)
        sig = Crypto.ecdsa_sign data, @raw_privkey
        raise InvalidSignatureError unless sig.size == 65
        sig
      end

      ##
      # ECIES Encrypt, where P = recipient publie key, is:
      #
      # 1. generate r = random value
      # 2. generate shared-secret = kdf( ecdhAgree(r, P) )
      # 3. generate R = rG [ same op as generating a public key ]
      # 4. send 0x04 || R || AsymmetricEncrypt(shared-secret, plaintext) || tag
      #
      def ecies_encrypt(data, remote_pubkey, shared_mac_data='')
        # 1. generate r = random value
        ephem = ECCx.new

        # 2. generate shared-secret = kdf( ecdhAgree(r, P) )
        key_material = ephem.get_ecdh_key(remote_pubkey)
        raise InvalidKeyError unless key_material.size == 32

        key = eciesKDF key_material, 32
        raise InvalidKeyError unless key.size == 32
        key_enc, key_mac = key[0,16], key[16,16]

        key_mac = Digest::SHA256.digest(key_mac)
        raise InvalidKeyError unless key_mac.size == 32

        # 3. generate R = rG
        ephem_pubkey = ephem.raw_pubkey

        ctx = OpenSSL::Cipher.new(CIPHER)
        ctx.encrypt
        ctx.key = key_enc
        iv = ctx.random_iv
        ctx.iv = iv

        ciphertext = ctx.update(data) + ctx.final
        raise EncryptionError unless ciphertext.size == data.size

        # 4. send 0x04 || R || AsymmetricEncrypt(shared-secret, plaintext) || tag
        tag = Crypto.hmac_sha256 key_mac, "#{iv}#{ciphertext}#{shared_mac_data}"
        raise InvalidMACError unless tag.size == 32
        msg = "\x04#{ephem_pubkey}#{iv}#{ciphertext}#{tag}"

        raise EncryptionError unless msg.size == ECIES_ENCRYPT_OVERHEAD_LENGTH + data.size
        msg
      end

      ##
      # Decrypt data with ECIES method using the local private key
      #
      # ECIES Decrypt (performed by recipient):
      #
      # 1. generate shared-secret = kdf( ecdhAgree(myPrivKey, msg[1,64]) )
      # 2. verify tag
      # 3. decrypt
      #
      # ecdhAgree(r, recipientPublic) == ecdhAgree(recipientPrivate, R)
      #   where R = r*G, recipientPublic = recipientPrivate * G
      #
      def ecies_decrypt(data, shared_mac_data='')
        raise DecryptionError, 'wrong ecies header' unless data[0] == "\x04"

        # 1. generate shared-secret = kdf( ecdhAgree(myPrivKey, msg[1,64]) )
        shared = data[1,64] # ephem_pubkey
        raise DecryptionError, 'invalid shared secret' unless valid_key?(shared)

        key_material = get_ecdh_key shared
        raise InvalidKeyError unless key_material.size == 32

        key = eciesKDF key_material, 32
        raise InvalidKeyError unless key.size == 32
        key_enc, key_mac = key[0,16], key[16,16]

        key_mac = Digest::SHA256.digest(key_mac)
        raise InvalidKeyError unless key_mac.size == 32

        tag = data[-32..-1]
        raise InvalidMACError unless tag.size == 32

        # 2. verify tag
        raise DecryptionError, 'Fail to verify data' unless Crypto.hmac_sha256(key_mac, "#{data[65...-32]}#{shared_mac_data}") == tag

        # 3. decrypt
        iv = data[65,CIPHER_BLOCK_SIZE]
        ciphertext = data[(65+CIPHER_BLOCK_SIZE)...-32]
        raise DecryptionError unless 1 + shared.size + iv.size + ciphertext.size + tag.size == data.size

        ctx = OpenSSL::Cipher.new CIPHER
        ctx.decrypt
        ctx.key = key_enc
        ctx.iv = iv

        ctx.update(ciphertext) + ctx.final
      end

      ##
      # interop w/go ecies implementation
      #
      # for sha3, blocksize is 136 bytes
      # for sha256, blocksize is 64 bytes
      #
      # NIST SP 800-56a Concatenation Key Derivation Function (section 5.8.1)
      #
      def eciesKDF(key_material, key_len)
        s1 = ""
        key = ""
        hash_blocksize = 64
        reps = ((key_len + 7) * 8) / (hash_blocksize * 8)
        counter = 0
        while counter <= reps
          counter += 1
          ctx = Digest::SHA256.new
          ctx.update [counter].pack('I>')
          ctx.update key_material
          ctx.update s1
          key += ctx.digest
        end
        key[0,key_len]
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

      def curve
        @curve ||= OpenSSL::PKey::EC.new(CURVE)
      end

      def set_curve
        curve.public_key = raw_pubkey_to_openssl_pubkey(@raw_pubkey)
        curve.private_key = raw_privkey_to_openssl_privkey(@raw_privkey)
      end

      def raw_pubkey_to_openssl_pubkey(raw_pubkey)
        bn = OpenSSL::BN.new Utils.encode_hex("\x04#{raw_pubkey}"), 16
        OpenSSL::PKey::EC::Point.new curve.group, bn
      end

      def raw_privkey_to_openssl_privkey(raw_privkey)
        OpenSSL::BN.new Utils.big_endian_to_int(raw_privkey)
      end

    end
  end
end
