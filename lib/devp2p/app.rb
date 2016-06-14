module DEVp2p
  class App
    include Concurrent::Async

    extend Configurable
    add_config(
      default_config: {
        client_version_string: "ruby-devp2p #{VersionString}",
        deactivated_services: []
      }
    )

    attr :config, :services

    def initialize(config=DEFAULT_CONFIG)
      super()

      @config = Hashie::Mash.new(default_config).merge(config)
      @services = Hashie::Mash.new
    end

    def register_service(klass, *args)
      raise ArgumentError, "service #{klass.name} already registered" if services.has_key?(klass.name)

      logger.info "registering service", service: klass.name
      services[klass.name] = klass.new *args
    end

    def deregister_service(klass)
      raise ArgumentError, "service #{klass.name} not registered" unless services.has_key?(klass.name)

      logger.info "deregistering service", service: klass.name
      services.delete klass.name
    end

    def start
      services.each_value do |service|
        service.async.start
      end
    end

    def stop
      services.each_value do |service|
        service.async.stop
      end
    end

    private

    def logger
      @logger ||= Logger.new 'app'
    end

  end
end
