# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Utils

    BYTE_ZERO = "\x00".freeze

    extend self

    def encode_hex(b)
      RLP::Utils.encode_hex b
    end

    def decode_hex(s)
      RLP::Utils.decode_hex s
    end

    def int_to_big_endian(i)
      RLP::Sedes.big_endian_int.serialize(i)
    end

    def big_endian_to_int(s)
      RLP::Sedes.big_endian_int.deserialize s.sub(/\A(\x00)+/, '')
    end

    # 4 bytes big endian integer
    def int_to_big_endian4(i)
      [i].pack('I>')
    end

    def ceil16(x)
      x % 16 == 0 ? x : (x + 16 - (x%16))
    end

    def lpad(x, symbol, l)
      return x if x.size >= l
      symbol * (l - x.size) + x
    end

    def zpad(x, l)
      lpad x, BYTE_ZERO, l
    end

    def bpad(x, l)
      lpad x.to_s(2), '0', l
    end

    def rzpad16(data)
      extra = data.size % 16
      data += "\x00" * (16 - extra) if extra != 0
      data
    end

    def zpad_int(i, l=32)
      Utils.zpad Utils.int_to_big_endian(i), l
    end

    ##
    # String xor.
    #
    def sxor(s1, s2)
      raise ArgumentError, "strings must have equal size" unless s1.size == s2.size

      s1.bytes.zip(s2.bytes).map {|a, b| (a ^ b).chr }.join
    end
 
    def update_config_with_defaults(config, default_config)
      default_config.each do |k, v|
        if v.is_a?(Hash)
          config[k] = update_config_with_defaults(config.fetch(k, {}), v)
        elsif !config.has_key?(k)
          config[k] = default_config[k]
        end
      end

      config
    end

    def host_port_pubkey_from_uri(uri)
      raise ArgumentError, 'invalid uri' unless uri =~ /\A#{NODE_URI_SCHEME}.+@.+:.+$/

      pubkey_hex, ip_port = uti[NODE_URI_SCHEME.size..-1].split('@')
      raise ArgumentError, 'invalid pubkey length' unless pubkey.size == 2 * Kademlia::PUBKEY_SIZE / 8

      ip, port = ip_port.split(':')
      return ip, port, Utils.decode_hex(pubkey_hex)
    end

    def host_port_pubkey_to_uri(host, port, pubkey)
      raise ArgumentError, 'invalid pubkey length' unless pubkey.size == Kademlia::PUBKEY_SIZE / 8

      "#{NODE_URI_SCHEME}#{encode_hex pubkey}@#{host}:#{port}"
    end

  end
end
