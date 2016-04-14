# -*- encoding : ascii-8bit -*-
module DEVp2p
  module Utils

    extend self

    def encode_hex(b)
      RLP::Utils.encode_hex b
    end

    def decode_hex(s)
      RLP::Utils.decode_hex s
    end

    def ceil16(x)
      x % 16 == 0 ? x : (x + 16 - (x%16))
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
