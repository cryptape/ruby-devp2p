# -*- encoding : ascii-8bit -*-
require 'test_helper'

require_relative 'example'

class AppTest < Minitest::Test
  include DEVp2p

  class ExampleServiceAppRestart < ExampleService
    attr_accessor :testdriver

    def initialize(app)
      super(app)
      after(0.5) { tick }
    end

    def on_wire_protocol_start(proto)
      my_version = @config[:node_num]

      if my_version == 0
        if testdriver[:app_restarted]
          testdriver[:test_successful] = true
        else
          app.stop
          sleep 1

          app.start
          testdriver[:app_restarted] = true
        end
      end
    end

    def tick
      if testdriver[:test_successful]
        app.stop
        return
      end

      after(0.5) { tick }
    end
  end

  ##
  # Test scenario:
  # - Restart the app on 1st node when the node is on_wire_protocol_start
  # - Check that this node gets on_wire_protocol_start at least once after restart
  #   - on_wire_protocol_start indicates that node was able to communicate after restart
  #
  def test_app_restart
    Celluloid.shutdown rescue nil
    Celluloid.boot

    AppHelper.new.run ExampleApp, ExampleServiceAppRestart, num_nodes: 3, min_peers: 2, max_peers: 2
  end

end
