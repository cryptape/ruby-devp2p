# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Configurable

    def add_config(configs)
      configs.each do |name, default|
        singleton_class.send(:define_method, name) do |*args|
          iv = "@#{name}"
          if args.empty?
            instance_variable_get(iv) || instance_variable_set(iv, default)
          else
            instance_variable_set(iv, args.first)
          end
        end
      end
    end

  end
end
