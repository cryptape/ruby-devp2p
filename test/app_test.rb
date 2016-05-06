# -*- encoding : ascii-8bit -*-
require 'test_helper'

require_relative 'example'

class AppTest < Minitest::Test
  include DEVp2p

  class ExampleServiceAppRestart < ExampleService

    class <<self
      attr_accessor :testdriver
    end

    def initialize(app)
      super(app)
      after(0.5) { tick }
    end

    def on_wire_protocol_start(proto)
      my_version = @config[:node_num]
      testdriver = self.class.testdriver

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
      if self.class.testdriver[:test_successful]
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
    skip "make it work with ExampleServiceAppRestart"

    Celluloid.shutdown rescue nil
    Celluloid.boot

    ExampleServiceAppRestart.testdriver = {
      app_restarted: false,
      test_successful: false
    }

    # TODO: make it work with max_peers=1
    AppHelper.new.run ExampleApp, ExampleServiceAppRestart, num_nodes: 2, min_peers: 1, max_peers: 2
    #sleep 40
  end

end
