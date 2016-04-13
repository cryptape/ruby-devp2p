# -*- encoding : ascii-8bit -*-
module DEVp2p

  ##
  # Service instances are added to the application under
  # `app.services.<service_name>`.
  #
  # App should be passed to the service in order to query other services.
  #
  # Services must be an actor. If a service spawns additional services, it's
  # responsible to stop them.
  #
  class BaseService
    include Celluloid

    DefaultConfig = {
      name: {}
    }

    class <<self
      def required_services
        @required_services ||= []
      end

      ##
      # Services know best how to initiate themselves. Create a service
      # instance, probably based on `app.config` and `app.services`.
      #
      def register_with_app(app)
        new(app).tap do |s|
          app.register_service s
        end
      end
    end

    attr :app

    def initialize(app)
      @app = app

      @config = Utils.update_config_with_defaults app.config, DefaultConfig
      @stopped = false

      available_services = app.services.each_value.map(&:class)
      self.class.required_services.each do |r|
        raise MissingRequiredServiceError, "require service #{r}" unless available_services.include?(r)
      end
    end

    def run
      # pass
    end

    def start
      @stopped = false
    end

    def stop
      @stopped = true
      terminate
    end

  end
end
