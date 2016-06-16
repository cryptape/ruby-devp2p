# -*- encoding : ascii-8bit -*-

module DEVp2p

  ##
  # monitors the connection by sending pings and checking pongs
  #
  class ConnectionMonitor
    include Concurrent::Async

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

      monitor = self
      # FIXME: sleep 1 to make sure ConnectionMonitor start after connection of
      # other protocols like ETHProtocol
      @proto.receive_hello_callbacks.push(->(p, **kwargs) { sleep 1; monitor.start })
    end

    def latency(num_samples=@max_samples)
      num_samples = [num_samples, @samples.size].min
      return 1 unless num_samples > 0
      (0...num_samples).map {|i| @samples[i] }.reduce(0, &:+)
    end

    def start
      logger.debug 'started', monitor: self

      logger.debug 'pinging', monitor: self
      @proto.async.send_ping
      now = @last_request = Time.now

      @task = Concurrent::TimerTask.new(execution_interval: @ping_interval) do
        logger.debug('latency', peer: @proto, latency: ("%.3f" % latency))

        if now - @last_response > @response_delay_threshold
          logger.debug "unresponsive_peer", monitor: self
          @proto.peer.async.report_error 'not responding to ping'
          @proto.async.stop
        end

        logger.debug 'pinging', monitor: self
        @proto.async.send_ping
        now = @last_request = Time.now
      end
      @task.execute
    rescue
      puts $!
      puts $!.backtrace[0,10].join("\n")
    end

    def stop
      logger.debug 'stopped', monitor: self
      @task.shutdown
      @task = nil
    end

    private

    def logger
      @logger ||= Logger.new("p2p.ctxmonitor")
    end

  end

end
