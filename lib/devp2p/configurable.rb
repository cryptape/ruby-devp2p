# -*- encoding : ascii-8bit -*-

module DEVp2p
  module Configurable

    def add_config(configs)
      raise ArgumentError, 'self must be a class' unless self.class == Class

      configs.each do |name, default|
        singleton_class.send(:define_method, name) do |*args|
          iv = "@#{name}"
          if args.empty?
            if instance_variable_defined?(iv)
              instance_variable_get(iv)
            else
              v = superclass.respond_to?(:add_config) && superclass.respond_to?(name) ?
                superclass.public_send(name) : default
              instance_variable_set(iv, v)
            end
          else
            instance_variable_set(iv, args.first)
          end
        end

        define_method(name) do |*args|
          self.class.public_send name, *args
        end
      end
    end

  end
end
