# -*- encoding : ascii-8bit -*-
require 'test_helper'

class MultiplexerTest < Minitest::Test
  include DEVp2p

  def setup
    @mux = Multiplexer.new
  end

  def test_frame
    p0 = 0
    @mux.add_protocol 0

    # test normal packet
    packet0 = Packet.new p0, 0, 'x'*100
    @mux.add_packet packet0

    frames = @mux.pop_frames
    assert_equal 1, frames.size

    f = frames.first
    message = f.as_bytes

    # check framing
    fs = f.frame_size
    assert_equal fs, message.size

    _fs = 16 + 16 + f.enc_cmd_id.size + packet0.payload.size + 16
    _fs += Frame.padding - _fs % Frame.padding
    assert_equal _fs, fs
    assert message[(32 + f.enc_cmd_id.size)..-1] =~ /\A#{packet0.payload}/

    packets = @mux.decode message
    assert_equal 0, @mux.decode_buffer.size
    assert_equal packet0.payload.size, packets[0].payload.size
    assert_equal packet0.payload, packets[0].payload
    assert_equal packet0, packets[0]
  end

end
