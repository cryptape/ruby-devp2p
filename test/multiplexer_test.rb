# -*- encoding : ascii-8bit -*-
require 'test_helper'

class MultiplexerTest < Minitest::Test
  include DEVp2p

  def setup
    @mux = Multiplexer.new
    @protos = [0,1,2]
    @protos.each {|id| @mux.add_protocol id }
  end

  def test_frame
    # test normal packet
    packet0 = Packet.new @protos[0], 0, 'x'*100
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

  def test_chunked
    packet1 = Packet.new @protos[1], 0, "\x00" * @mux.class.max_window_size * 2 + 'x'
    @mux.add_packet packet1

    frames = @mux.pop_all_frames
    assert_equal packet1.payload.size, frames.map(&:payload).map(&:size).reduce(0, &:+)

    all_frames_length = frames.map(&:frame_size).reduce(0, &:+)
    @mux.add_packet packet1
    message = @mux.pop_all_frames_as_bytes
    assert_equal all_frames_length, message.size

    packets = @mux.decode message
    assert_equal 0, @mux.decode_buffer.size
    assert_equal packet1.payload, packets[0].payload
    assert_equal packet1, packets[0]
    assert_equal 1, packets.size
  end

  def test_chunked_big
    logger = Logging.logger.root

    payload = "\x00" * 10 * 1024**2 # 10MB
    packet1 = Packet.new @protos[0], 0, payload
    logger.info "large payload size: #{payload.size}"

    t = Time.now
    @mux.add_packet packet1
    logger.info "framing: #{Time.now - t}"

    t = Time.now
    messages = @mux.pop_all_frames.map(&:as_bytes)
    logger.info "popping frames: #{Time.now - t}"

    t = Time.now
    packets = nil
    messages.each do |m|
      packets = @mux.decode m
      break unless packets.empty?
    end
    logger.info "decoding frames: #{Time.now - t}"

    assert_equal 0, @mux.decode_buffer.size
    assert_equal packet1.payload, packets[0].payload
    assert_equal packet1, packets[0]
    assert_equal 1, packets.size
  end

  def test_remain
    packet1 = Packet.new @protos[1], 0, "\x00"*100
    @mux.add_packet packet1
    message = @mux.pop_all_frames_as_bytes

    tail = message[0,50]
    message += tail
    packets = @mux.decode message

    assert_equal packet1, packets[0]
    assert_equal 1, packets.size
    assert_equal tail.size, @mux.decode_buffer.size

    message = message[1..-1]
    assert_raises(MultiplexerError) { @mux.decode message }
  end

  def test_multiplexer
    assert_equal @protos[0], @mux.next_protocol
    assert_equal @protos[1], @mux.next_protocol
    assert_equal @protos[2], @mux.next_protocol
    assert_equal @protos[0], @mux.next_protocol

    assert_equal [], @mux.pop_frames
    assert_equal 0, @mux.num_active_protocols

    packet0 = Packet.new @protos[0], 0, 'x'*100
    @mux.add_packet packet0
    assert_equal 1, @mux.num_active_protocols

    frames = @mux.pop_frames
    assert_equal 1, frames.size
    assert_equal frames[0].frame_size, frames[0].as_bytes.size

    @mux.add_packet packet0
    assert_equal 1, @mux.num_active_protocols
    message = @mux.pop_all_frames_as_bytes
    packets = @mux.decode message
    assert_equal packet0.payload.size, packets[0].payload.size
    assert_equal packet0.payload, packets[0].payload
    assert_equal packet0, packets[0]

    assert_equal 0, @mux.pop_frames.size

    # big packet
    packet1 = Packet.new @protos[1], 0, "\x00"* @mux.class.max_window_size * 2
    @mux.add_packet packet1

    message = @mux.pop_all_frames_as_bytes
    packets = @mux.decode message
    assert_equal packet1.payload, packets[0].payload
    assert_equal packet1, packets[0]
    assert_equal 1, packets.size

    # mix packet types
    packet2 = Packet.new @protos[0], 0, "\x00"*200, true
    @mux.add_packet packet1
    @mux.add_packet packet0
    @mux.add_packet packet2
    message = @mux.pop_all_frames_as_bytes
    packets = @mux.decode message
    assert_equal [packet2, packet0, packet1], packets

    # packets with different protocols
    packet3 = Packet.new @protos[1], 0, "\x00"*3000, false
    @mux.add_packet packet1
    @mux.add_packet packet0
    @mux.add_packet packet2
    @mux.add_packet packet3
    @mux.add_packet packet3
    @mux.add_packet packet3
    assert_equal @protos[0], @mux.next_protocol

    # thus next with data is p1 with packet3
    message = @mux.pop_all_frames_as_bytes
    packets = @mux.decode message
    assert_equal [packet3, packet2, packet0, packet3, packet3, packet1], packets

    # test buffer remains, incomplete frames
    packet1 = Packet.new @protos[1], 0, "\x00"*100
    @mux.add_packet packet1

    message = @mux.pop_all_frames_as_bytes
    tail = message[0,50]
    message += tail
    packets = @mux.decode message

    assert_equal packet1, packets[0]
    assert_equal 1, packets.size
    assert_equal tail.size, @mux.decode_buffer.size
  end

end
