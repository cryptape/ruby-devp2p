# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # monitors the connection by sending pings and checking pongs
  #
  class ConnectionMonitor
    include Celluloid

    def initialize(proto)
      @proto = proto

      logger.debug "init"
      raise ArgumentError, 'protocol must be P2PProtocol' unless proto.is_a?(P2PProtocol)

      @samples = []
      @last_response = @last_request = Time.now

      @ping_interval = 15
      @response_delay_threshold = 120
      @max_samples = 1000

      track_response = ->(proto, **data) {
        @last_response = Time.now
        @samples.unshift(@last_response - @last_request)
        @samples.pop if @samples.size > @max_samples
      }
      @proto.receive_pong_callbacks.push(track_response)

      monitor = Actor.current
      @proto.receive_hello_callbacks.push(->(p, **kwargs) { monitor.start })
    end

    def latency(num_samples=@max_samples)
      num_samples = [num_samples, @samples.size].min
      return 1 unless num_samples > 0
      (0...num_samples).map {|i| @samples[i] }.reduce(0, &:+)
    end

    def run
      logger.debug 'started', monitor: Actor.current
      loop do
        logger.debug 'pinging', monitor: Actor.current
        @proto.send_ping

        now = @last_request = Time.now
        sleep @ping_interval
        logger.debug('latency', peer: @proto, latency: ("%.3f" % latency))

        if now - @last_response > @response_delay_threshold
          logger.debug "unresponsive_peer", monitor: Actor.current
          @proto.peer.report_error 'not responding to ping'
          @proto.stop
          terminate
        end
      end
    end

    def start
      async.run
    end

    def stop
      logger.debug 'stopped', monitor: Actor.current
      terminate
    end

    private

    def logger
      @logger ||= Logger.new("#{@proto.peer.config[:p2p][:listen_port]}.p2p.ctxmonitor.#{object_id}")
    end

  end

end
