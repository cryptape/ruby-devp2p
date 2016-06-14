require 'hashie'

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

    def initialize(config=default_config)
      super()

      @config = Hashie::Mash.new(default_config).merge(config)
      @registry = {}
      @services = Hashie::Mash.new
    end

    def register_service(klass, *args)
      raise ArgumentError, "service #{klass.name} already registered" if services.has_key?(klass.name)

      logger.info "registering service", service: klass.name
      @registry[klass.name] = [klass, args]
    end

    def deregister_service(klass)
      raise ArgumentError, "service #{klass.name} not registered" unless services.has_key?(klass.name)

      logger.info "deregistering service", service: klass.name
      services[klass.name].async.stop
      services.delete klass.name
      @registry.delete klass.name
    end

    def start
      @registry.each do |name, (klass, args)|
        services[name] = klass.new(*args)
        services[name].async.start
      end
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    def stop
      services.keys.each do |name|
        services[name].async.stop
        services.delete name
      end
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    private

    def logger
      @logger ||= Logger.new 'app'
    end

  end
end
