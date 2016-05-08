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
      @container = Celluloid::Supervision::Container.new
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
      @container.add type: klass, as: get_actor_name(klass.name), args: args
      services[klass.name] = actor(klass.name)

      klass
    end

    ##
    # Terminate service instance, remove it from registry.
    #
    def deregister_service(klass)
      raise ArgumentError, "service must be instance of BaseService" unless klass.instance_of?(Class) && klass < BaseService
      raise ArgumentError, "service #{klass.name} not registered" unless services.has_key?(klass.name)

      logger.info "deregistering service", service: klass.name
      @container.remove actor(klass.name)
      services.delete klass.name

      klass
    end

    def start
      services.each_value do |service|
        service.start if service.stopped?
      end
    end

    def stop
      services.each_value do |service|
        service.stop if service.alive?
      end

      #@container.shutdown
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

    def actor(name)
      Celluloid::Actor[get_actor_name(name)]
    end

    def get_actor_name(service_name)
      "#{object_id}_#{service_name}"
    end

  end
end
