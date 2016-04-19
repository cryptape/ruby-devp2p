# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Crypto
    class ECIES

      CIPHER = 'AES-128-CTR'.freeze
      CIPHER_BLOCK_SIZE = 16 # 128 / 8

      ENCRYPT_OVERHEAD_LENGTH = 113

      class <<self

        ##
        # ECIES Encrypt, where P = recipient publie key, is:
        #
        # 1. generate r = random value
        # 2. generate shared-secret = kdf( ecdhAgree(r, P) )
        # 3. generate R = rG [ same op as generating a public key ]
        # 4. send 0x04 || R || AsymmetricEncrypt(shared-secret, plaintext) || tag
        #
        def encrypt(data, remote_pubkey, shared_mac_data='')
          # 1. generate r = random value
          ephem = ECCx.new

          # 2. generate shared-secret = kdf( ecdhAgree(r, P) )
          key_material = ephem.get_ecdh_key remote_pubkey
          raise InvalidKeyError unless key_material.size == 32

          key = kdf key_material, 32
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

          raise EncryptionError unless msg.size == ENCRYPT_OVERHEAD_LENGTH + data.size
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
        def decrypt(curve, data, shared_mac_data='')
          raise DecryptionError, 'wrong ecies header' unless data[0] == "\x04"

          # 1. generate shared-secret = kdf( ecdhAgree(myPrivKey, msg[1,64]) )
          shared = data[1,64] # ephem_pubkey
          raise DecryptionError, 'invalid shared secret' unless ECCx.valid_key?(shared)

          key_material = ECCx.get_ecdh_key curve, shared
          raise InvalidKeyError unless key_material.size == 32

          key = kdf key_material, 32
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
        def kdf(key_material, key_len)
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

      end
    end
  end
end
