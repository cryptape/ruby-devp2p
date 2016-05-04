# -*- encoding : ascii-8bit -*-
require 'hashie'

module DEVp2p
  class BaseApp

    extend Configurable
    add_config(
      default_config: {
        client_version_string: "ruby-devp2p #{VersionString}",
        deactivated_services: []
      }
    )

    attr :config, :services

    def initialize(config=default_config)
      @config = Utils.update_config_with_defaults config, default_config
      @registry = Celluloid::Supervision::Configuration.new
      @services = Hashie::Mash.new
    end

    ##
    # Registers protocol with app, which will be accessible as
    # `app.services.<protocol_name>` (e.g. `app.services.p2p` or
    # `app.services.eth`)
    #
    def register_service(klass, *args)
      raise ArgumentError, "service must be instance of BaseService" unless klass.instance_of?(Class) && klass < BaseService
      raise ArgumentError, "service #{klass.name} already registered" if services.has_key?(klass.name)

      logger.info "registering service", service: klass.name

      @registry.define type: klass, as: klass.name, args: args
      services[klass.name] = nil
    end

    def deregister_service(service)
      raies NotImplemented
      #raise ArgumentError, "service must be instance of BaseService" unless service.is_a?(BaseService)
      #services.delete(service.name)
      #unlink service
    end

    def start
      @registry.deploy

      services.keys.each do |k|
        services[k] = Celluloid::Actor[k]
        services[k].start
      end
    end

    def stop
      @registry.shutdown
    end

    def join
      @services.each_value do |service|
        Celluloid::Actor.join service
      end
    end

    private

    def logger
      @logger ||= Logger.new 'app'
    end

  end
end
