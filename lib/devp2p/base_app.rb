# -*- encoding : ascii-8bit -*-
require 'hashie'

module DEVp2p
  class BaseApp

    DefaultConfig = {
      client_version_string: "ruby-devp2p #{VersionString}",
      deactivated_services: []
    }

    attr :config, :services

    def initialize(config=DefaultConfig)
      @config = Utils.update_config_with_defaults config, DefaultConfig
      @services = Hashie::Mash.new
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

      services[service.name] = service
    end

    def deregister_service(service)
      raise ArgumentError, "service must be instance of BaseService" unless service.is_a?(BaseService)
      services.delete(service.name)
    end

    def start
      services.each_value(&:start)
    end

    def stop
      services.each_value(&:stop)
    end

    private

    def logger
      @logger ||= Logger.new 'app'
    end

  end
end
