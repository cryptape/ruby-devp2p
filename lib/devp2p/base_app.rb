# -*- encoding : ascii-8bit -*-
require 'hashie'

module DEVp2p
  class BaseApp
    include Celluloid
    trap_exit :service_died

    DefaultConfig = {
      client_version_string: "ruby-devp2p #{VersionString}",
      deactivated_services: []
    }

    attr :config, :registry, :services

    def initialize(config=DefaultConfig)
      @config = Utils.update_config_with_defaults config, DefaultConfig
      @services = Hashie::Mash.new # active services
      @registry = {} # registered services
    end

    ##
    # Registers protocol with app, which will be accessible as
    # `app.services.<protocol_name>` (e.g. `app.services.p2p` or
    # `app.services.eth`)
    #
    def register_service(service)
      raise ArgumentError, "service must be instance of BaseService" unless service.is_a?(BaseService)
      raise ArgumentError, "service #{service.name} already registered" if services.has_key?(service.name)

      logger.info "registering service", service: service.name

      @registry[service.name] = service.class
      services[service.name] = service
      link service

      service
    end

    def deregister_service(service)
      raise ArgumentError, "service must be instance of BaseService" unless service.is_a?(BaseService)
      @registry.delete(service.name)
      services.delete(service.name)
      unlink service
    end

    def start
      @registry.each do |name, klass|
        klass.register_with_app(Actor.current) unless services.has_key?(name)
      end

      services.each_value(&:start)
    end

    def stop
      services.each_value(&:stop)
      #terminate
    end

    private

    def logger
      @logger ||= Logger.new 'app'
    end

    def service_died(service, reason)
      logger.info "service died", reason: reason
      services.delete_if {|k, v| v == service }
    end

  end
end
