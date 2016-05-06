# -*- encoding : ascii-8bit -*-
require 'test_helper'

class BaseServiceTest < Minitest::Test
  include DEVp2p

  class TestService < BaseService
    attr :counter

    def initialize(app)
      super(app)
      @counter = 0
    end

    private

    def _run
      loop do
        @counter += 1
        sleep 0.01
      end
    end

  end

  def test_base_service
    Celluloid.shutdown rescue nil
    Celluloid.boot

    app = BaseApp.new

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
