# -*- encoding : ascii-8bit -*-

module DEVp2p

  class Service
    include Concurrent::Async

    extend Configurable
    add_config(
      name: '',
      default_config: {},
      required_services: []
    )

    class <<self
      def register_with_app(app)
        app.register_service self, app
      end
    end

    attr :app, :config

    def initialize(app)
      super()

      @app = app
      @config = app.config.reverse_merge(default_config)

      available_services = app.services.each_value.map(&:class)
      required_services.each do |r|
        raise MissingRequiredServiceError, "require service #{r}" unless available_services.include?(r)
      end
    end

    def start
      raise NotImplemented
    end

    def stop
      raise NotImplemented
    end

    def to_s
      "<Service #{name}##{object_id}>"
    end
    alias inspect to_s

  end

end
