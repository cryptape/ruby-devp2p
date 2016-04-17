# -*- encoding : ascii-8bit -*-

require 'digest/sha3'

module DEVp2p
  module Utils

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

    def ceil16(x)
      x % 16 == 0 ? x : (x + 16 - (x%16))
    end

    def rzpad16(data)
      extra = data.size % 16
      data += "\x00" * (16 - extra) if extra != 0
      data
    end

    ##
    # String xor.
    #
    def sxor(s1, s2)
      raise ArgumentError, "strings must have equal size" unless s1.size == s2.size

      s1.bytes.zip(s2.bytes).map {|a, b| (a ^ b).chr }.join
    end
 
    def keccak256(x)
      Digest::SHA3.new(256).digest(x)
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

  end
end
