module DEVp2p
  module Control

    def initialize_control
      @stopped = false
      @killed = false
    end

    def run
      _run
    end

    def start
      @stopped = false
      async.run unless killed?
    end

    def stop
      @stopped = true
      @killed = true
    end

    def stopped?
      @stopped
    end

    def killed?
      @killed
    end

  end
end
