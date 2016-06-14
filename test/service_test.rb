# -*- encoding : ascii-8bit -*-
require 'test_helper'

class ServiceTest < Minitest::Test
  include DEVp2p

  class TestService < Service
    attr :counter

    def initialize(app)
      super(app)
      @counter = 0
    end

    def start
      @run = Thread.new do
        loop do
          @counter += 1
          sleep 0.01
        end
      end
    end

    def stop
      @run.kill
    end
  end

  def test_base_service
    app = App.new

    klass = TestService.register_with_app app
    assert_equal '', klass.name

    # register another service
    TestService.name 'other'
    klass2 = TestService.register_with_app app

    app.start
    sleep 0.1

    s = app.services[klass.name]
    s2 = app.services[klass2.name]

    assert s.counter > 0
    assert s2.counter > 0
    assert (s.counter - s2.counter) <= 2

    app.stop
  end

end
