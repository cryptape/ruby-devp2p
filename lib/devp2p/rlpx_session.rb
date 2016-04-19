# -*- encoding : ascii-8bit -*-

require 'securerandom'
require 'digest/sha3'

module DEVp2p
  class RLPxSession

    SUPPORTED_RLPX_VERSION = 4

    ENC_CIPHER = 'AES-256-CTR'
    MAC_CIPHER = 'AES-256-ECB'

    extend Configurable
    add_config(
      eip8_auth_sedes: RLP::Sedes::List.new(
        elements: [
          RLP::Sedes::Binary.new(min_length: 65, max_length: 65), # sig
          RLP::Sedes::Binary.new(min_length: 64, max_length: 64), # pubkey
          RLP::Sedes::Binary.new(min_length: 32, max_length: 32), # nonce
          RLP::Sedes::BigEndianInt.new,                           # version
        ],
        strict: false
      ),
      eip8_ack_sedes: RLP::Sedes::List.new(
        elements: [
          RLP::Sedes::Binary.new(min_length: 64, max_length: 64), # ephemeral pubkey
          RLP::Sedes::Binary.new(min_length: 32, max_length: 32), # nonce
          RLP::Sedes::BigEndianInt.new                            # version
        ],
        strict: false
      )
    )

    attr :ecc, :ephemeral_ecc,
      :initiator_nonce, :responder_nonce,
      :remote_version, :remote_pubkey, :remote_ephemeral_pubkey

    def initialize(ecc, is_initiator=false, ephemeral_privkey=nil)
      @ecc = ecc
      @is_initiator = is_initiator
      @ephemeral_ecc = Crypto::ECCx.new ephemeral_privkey

      @ready = false
      @got_eip8_auth, @got_eip8_ack = false, false
    end

    ### Frame Handling

    def encrypt(header, frame)
      raise RLPxSessionError, 'not ready' unless ready?
      raise ArgumentError, 'invalid header length' unless header.size == 16
      raise ArgumentError, 'invalid frame padding' unless frame.size % 16 == 0

      header_ciphertext = aes_enc header
      raise RLPxSessionError unless header_ciphertext.size == header.size
      header_mac = egress_mac(Utils.sxor(mac_enc(egress_mac[0,16]), header_ciphertext))[0,16]

      frame_ciphertext = aes_enc frame
      raise RLPxSessionError unless frame_ciphertext.size == frame.size
      fmac_seed = egress_mac frame_ciphertext
      frame_mac = egress_mac(Utils.sxor(mac_enc(egress_mac[0,16]), fmac_seed[0,16]))[0,16]

      header_ciphertext + header_mac + frame_ciphertext + frame_mac
    end

    def decrypt_header(data)
      raise RLPxSessionError, 'not ready' unless ready?
      raise ArgumentError, 'invalid data length' unless data.size == 32

      header_ciphertext = data[0,16]
      header_mac = data[16,16]

      expected_header_mac = ingress_mac(Utils.sxor(mac_enc(ingress_mac[0,16]), header_ciphertext))[0,16]
      raise AuthenticationError, 'invalid header mac' unless expected_header_mac == header_mac

      aes_dec header_ciphertext
    end

    def decrypt_body(data, body_size)
      raise RLPxSessionError, 'not ready' unless ready?

      read_size = Utils.ceil16 body_size
      raise FormatError, 'insufficient body length' unless data.size >= read_size + 16

      frame_ciphertext = data[0, read_size]
      frame_mac = data[read_size, 16]
      raise RLPxSessionError, 'invalid frame mac length' unless frame_mac.size == 16

      fmac_seed = ingress_mac frame_ciphertext
      expected_frame_mac = ingress_mac(Utils.sxor(mac_enc(ingress_mac[0,16]), fmac_seed[0,16]))[0,16]
      raise AuthenticationError, 'invalid frame mac' unless expected_frame_mac == frame_mac

      aes_dec(frame_ciphertext)[0,body_size]
    end

    def decrypt(data)
      header = decrypt_header data[0,32]
      body_size = Frame.decode_body_size header

      len = 32 + Utils.ceil16(body_size) + 16
      raise FormatError, 'insufficient body length' unless data.size >= len

      frame = decrypt_body data[32..-1], body_size
      {header: header, frame: frame, bytes_read: len}
    end

    ### Handshake Auth Message Handling

    ##
    # 1. initiator generates ecdhe-random and nonce and creates auth
    # 2. initiator connects to remote and sends auth
    #
    # New:
    #
    #   E(remote-pubk,
    #     S(ephemeral-privk, ecdh-shared-secret ^ nonce) ||
    #     H(ephemeral-pubk) || pubk || nonce || 0x0
    #   )
    #
    # Known:
    #
    #   E(remote-pubk,
    #     S(ephemeral-privk, token ^ nonce) ||
    #     H(ephemeral-pubk) || pubk || nonce || 0x1
    #   )
    #
    def create_auth_message(remote_pubkey, ephemeral_privkey=nil, nonce=nil)
      raise RLPxSessionError, 'must be initiator' unless initiator?
      raise InvalidKeyError, 'invalid remote pubkey' unless Crypto::ECCx.valid_key?(remote_pubkey)

      @remote_pubkey = remote_pubkey

      token = @ecc.get_ecdh_key remote_pubkey
      flag = 0x0

      @initiator_nonce = nonce || Utils.keccak256(Utils.int_to_big_endian(SecureRandom.random_number(TT256)))
      raise RLPxSessionError, 'invalid nonce length' unless @initiator_nonce.size == 32

      token_xor_nonce = Utils.sxor token, @initiator_nonce
      raise RLPxSessionError, 'invalid token xor nonce length' unless token_xor_nonce.size == 32

      ephemeral_pubkey = @ephemeral_ecc.raw_pubkey
      raise InvalidKeyError, 'invalid ephemeral pubkey' unless ephemeral_pubkey.size == 512 / 8 && Crypto::ECCx.valid_key?(ephemeral_pubkey)

      sig = @ephemeral_ecc.sign token_xor_nonce
      raise RLPxSessionError, 'invalid signature' unless sig.size == 65

      auth_message = "#{sig}#{Utils.keccak256(ephemeral_pubkey)}#{@ecc.raw_pubkey}#{@initiator_nonce}#{flag.chr}"
      raise RLPxSessionError, 'invalid auth message length' unless auth_message.size == 194

      auth_message
    end

    def encrypt_auth_message(auth_message, remote_pubkey=nil)
      raise RLPxSessionError, 'must be initiator' unless initiator?

      remote_pubkey ||= @remote_pubkey
      @auth_init = @ecc.ecies_encrypt auth_message, remote_pubkey
      raise RLPxSessionError, 'invalid encrypted auth message length' unless @auth_init.size == 307

      @auth_init
    end

    ##
    # 3. optionally, remote decrypts and verifies auth (checks that recovery of
    #   signature == H(ephemeral-pubk))
    # 4. remote generates authAck from remote-ephemeral-pubk and nonce (authAck
    #   = authRecipient handshake)
    #
    # optional: remote derives secrets and preemptively sends
    # protocol-handshake (steps 9,11,8,10)
    #
    def decode_authentication(ciphertext)
      raise RLPxSessionError, 'must not be initiator' if initiator?
      raise ArgumentError, 'invalid ciphertext length' unless ciphertext.size >= 307

      result = nil
      begin
        result = decode_auth_plain ciphertext
      rescue AuthenticationError
        result = decode_auth_eip8 ciphertext
        @got_eip8_auth = true
      end
      size, sig, initiator_pubkey, nonce, version = result

      @auth_init = ciphertext[0, size]

      token = @ecc.get_ecdh_key initiator_pubkey
      @remote_ephemeral_pubkey = Crypto.ecdsa_recover(Utils.sxor(token, nonce), sig)
      raise InvalidKeyError, 'invalid remote ephemeral pubkey' unless Crypto::ECCx.valid_key?(@remote_ephemeral_pubkey)

      @initiator_nonce = nonce
      @remote_pubkey = initiator_pubkey
      @remote_version = version

      ciphertext[size..-1]
    end

    ### Handshake ack message handling

    ##
    # authRecipient = E(remote-pubk, remote-ephemeral-pubk || nonce || 0x1) // token found
    # authRecipient = E(remote-pubk, remote-ephemeral-pubk || nonce || 0x0) // token not found
    #
    # nonce, ephemeral_pubkey, version are local
    #
    def create_auth_ack_message(ephemeral_pubkey=nil, nonce=nil, version=SUPPORTED_RLPX_VERSION, eip8=false)
      raise RLPxSessionError, 'must not be initiator' if initiator?

      ephemeral_pubkey = ephemeral_pubkey || @ephemeral_ecc.raw_pubkey
      @responder_nonce = nonce || Utils.keccak256(Utils.int_to_big_endian(SecureRandom.random_number(TT256)))

      if eip8 || @got_eip8_auth
        msg = create_eip8_auth_ack_message ephemeral_pubkey, @responder_nonce, version
        raise RLPxSessionError, 'invalid msg size' unless msg.size > 97
      else
        msg = "#{ephemeral_pubkey}#{@responder_nonce}\x00"
        raise RLPxSessionError, 'invalid msg size' unless msg.size == 97
      end

      msg
    end

    def create_eip8_auth_ack_message(ephemeral_pubkey, nonce, version)
      data = RLP.encode [ephemeral_pubkey, nonce, version], sedes: self.class.eip8_ack_sedes
      pad = SecureRandom.random_bytes(SecureRandom.random_number(151)+100) # (100..150) random bytes
      "#{data}#{pad}"
    end

    def encrypt_auth_ack_message(ack_message, eip8=false, remote_pubkey=nil)
      raise RLPxSessionError, 'must not be initiator' if initiator?

      remote_pubkey ||= @remote_pubkey

      if eip8 || @got_eip8_auth
        # The EIP-8 version has an authenticated length prefix
        prefix = [ack_message.size + Crypto::ECIES::ENCRYPT_OVERHEAD_LENGTH].pack("S>")
        @auth_ack = "#{prefix}#{@ecc.ecies_encrypt(ack_message, remote_pubkey, prefix)}"
      else
        @auth_ack = @ecc.ecies_encrypt ack_message, remote_pubkey
        raise RLPxSessionError, 'invalid auth ack message length' unless @auth_ack.size == 210
      end

      @auth_ack
    end

    def decode_auth_ack_message(ciphertext)
      raise RLPxSessionError, 'must be initiator' unless initiator?
      raise ArgumentError, 'invalid ciphertext length' unless ciphertext.size >= 210

      result = nil
      begin
        result = decode_ack_plain ciphertext
      rescue AuthenticationError
        result = decode_ack_eip8 ciphertext
        @got_eip8_ack = true
      end
      size, ephemeral_pubkey, nonce, version = result

      @auth_ack = ciphertext[0,size]
      @remote_ephemeral_pubkey = ephemeral_pubkey[0,64]
      @responder_nonce = nonce
      @remote_version = version

      raise InvalidKeyError, 'invalid remote ephemeral pubkey' unless Crypto::ECCx.valid_key?(@remote_ephemeral_pubkey)

      ciphertext[size..-1]
    end

    ### Handshake Key Derivation

    def setup_cipher
      raise RLPxSessionError, 'missing responder nonce' unless @responder_nonce
      raise RLPxSessionError, 'missing initiator_nonce' unless @initiator_nonce
      raise RLPxSessionError, 'missing auth_init' unless @auth_init
      raise RLPxSessionError, 'missing auth_ack' unless @auth_ack
      raise RLPxSessionError, 'missing remote ephemeral pubkey' unless @remote_ephemeral_pubkey
      raise InvalidKeyError, 'invalid remote ephemeral pubkey' unless Crypto::ECCx.valid_key?(@remote_ephemeral_pubkey)

      # derive base secrets from ephemeral key agreement
      # ecdhe-shared-secret = ecdh.agree(ephemeral-privkey, remote-ephemeral-pubk)
      @ecdhe_shared_secret = @ephemeral_ecc.get_ecdh_key(@remote_ephemeral_pubkey)
      @shared_secret = Utils.keccak256("#{@ecdhe_shared_secret}#{Utils.keccak256(@responder_nonce + @initiator_nonce)}")
      @token = Utils.keccak256 @shared_secret
      @aes_secret = Utils.keccak256 "#{@ecdhe_shared_secret}#{@shared_secret}"
      @mac_secret = Utils.keccak256 "#{@ecdhe_shared_secret}#{@aes_secret}"

      mac1 = keccak256 "#{Utils.sxor(@mac_secret, @responder_nonce)}#{@auth_init}"
      mac2 = keccak256 "#{Utils.sxor(@mac_secret, @initiator_nonce)}#{@auth_ack}"

      if initiator?
        @egress_mac, @ingress_mac = mac1, mac2
      else
        @egress_mac, @ingress_mac = mac2, mac1
      end

      iv = "\x00" * 16
      @aes_enc = OpenSSL::Cipher.new(ENC_CIPHER).tap do |c|
        c.encrypt
        c.iv = iv
        c.key = @aes_secret
      end
      @aes_dec = OpenSSL::Cipher.new(ENC_CIPHER).tap do |c|
        c.decrypt
        c.iv = iv
        c.key = @aes_secret
      end
      @mac_enc = OpenSSL::Cipher.new(MAC_CIPHER).tap do |c|
        c.encrypt
        c.key = @mac_secret
      end

      @ready = true
    end

    ### Helpers

    def ready?
      @ready
    end

    def initiator?
      @is_initiator
    end

    def mac_enc(data)
      @mac_enc.update data
    end

    def aes_enc(data='')
      @aes_enc.update data
    end

    def aes_dec(data='')
      @aes_dec.update data
    end

    def egress_mac(data='')
      @egress_mac.update data
      return @egress_mac.digest
    end

    def ingress_mac(data='')
      @ingress_mac.update data
      return @ingress_mac.digest
    end

    private

    def keccak256(x)
      Digest::SHA3.new(256).tap {|d| d.update x }
    end

    ##
    # decode legacy pre-EIP-8 auth message format
    #
    def decode_auth_plain(ciphertext)
      message = begin
                  @ecc.ecies_decrypt ciphertext[0,307]
                rescue
                  raise AuthenticationError, $!
                end
      raise RLPxSessionError, 'invalid message length' unless message.size == 194

      sig = message[0,65]
      pubkey = message[65+32,64]
      raise InvalidKeyError, 'invalid initiator pubkey' unless Crypto::ECCx.valid_key?(pubkey)

      nonce = message[65+32+64,32]
      flag = message[(65+32+64+32)..-1].ord
      raise RLPxSessionError, 'invalid flag' unless flag == 0

      [307, sig, pubkey, nonce, 4]
    end

    ##
    # decode EIP-8 auth message format
    #
    def decode_auth_eip8(ciphertext)
      size = ciphertext[0,2].unpack('S>').first + 2
      raise RLPxSessionError, 'invalid ciphertext size' unless ciphertext.size >= size

      message = begin
                  @ecc.ecies_decrypt ciphertext[2...size], ciphertext[0,2]
                rescue
                  raise AuthenticationError, $!
                end

      values = RLP.decode message, sedes: self.class.eip8_auth_sedes, strict: false
      raise RLPxSessionError, 'invalid values size' unless values.size >= 4

      [size] + values[0,4]
    end

    ##
    # decode legacy pre-EIP-8 ack message format
    #
    def decode_ack_plain(ciphertext)
      message = begin
                  @ecc.ecies_decrypt ciphertext[0,210]
                rescue
                  raise AuthenticationError, $!
                end
      raise RLPxSessionError, 'invalid message length' unless message.size == 64+32+1

      ephemeral_pubkey = message[0,64]
      nonce = message[64,32]
      known = message[-1].ord
      raise RLPxSessionError, 'invalid known byte' unless known == 0

      [210, ephemeral_pubkey, nonce, 4]
    end

    ##
    # decode EIP-8 ack message format
    #
    def decode_ack_eip8(ciphertext)
      size = ciphertext[0,2].unpack('S>').first + 2
      raise RLPxSessionError, 'invalid ciphertext length' unless ciphertext.size == size

      message = begin
                  @ecc.ecies_decrypt(ciphertext[2...size], ciphertext[0,2])
                rescue
                  raise AuthenticationError, $!
                end
      values = RLP.decode message, sedes: self.class.eip8_ack_sedes, strict: false
      raise RLPxSessionError, 'invalid values length' unless values.size >= 3

      [size] + values[0,3]
    end

  end
end
