# -*- encoding : ascii-8bit -*-
require 'test_helper'

require 'set'

class KademliaTest < Minitest::Test
  include DEVp2p

  def test_routing_table
    routing_table 1000
  end

  def test_split
    node = random_node
    routing = Kademlia::RoutingTable.new node
    assert_equal 1, routing.buckets_count

    # create very close nodes
    Kademlia::K.times do |i|
      node = fake_node_from_id node.id + 1
      assert ivget(routing, :@buckets)[0].in_range?(node)

      routing.add node
      assert_equal 1, routing.buckets_count
    end

    assert_equal Kademlia::K, ivget(routing, :@buckets)[0].size

    node = fake_node_from_id node.id + 1
    assert ivget(routing, :@buckets)[0].in_range?(node)

    routing.add node
    assert ivget(routing, :@buckets)[0].size <= Kademlia::K
    assert routing.buckets_count <= 512
  end

  def test_split2
    routing = routing_table(10000)

    full_buckets = ivget(routing, :@buckets).select {|b| b.full? }
    split_buckets = ivget(routing, :@buckets).select {|b| b.should_split? }
    assert split_buckets.size < full_buckets.size
    assert Set.new(split_buckets).subset?(Set.new(full_buckets))

    bucket = full_buckets[0]
    assert !bucket.should_split?
    assert Kademlia::K, bucket.size

    node = fake_node_from_id bucket.left+1
    assert !bucket.include?(node)
    assert bucket.in_range?(node)
    assert_equal bucket, routing.bucket_by_node(node)

    r = bucket.add node
    assert r
  end

  def test_non_overlap
    routing = routing_table 1000

    max_id = 0
    ivget(routing, :@buckets).each_with_index do |b, i|
      assert b.left > max_id if i > 0
      assert b.right > max_id
      max_id = b.right
      assert_equal 2**Kademlia::ID_SIZE - 1, b.right if i == routing.buckets_count - 1
    end
  end

  def test_full_range
    [1, 16, 17, 1000].each do |num_nodes|
      routing = routing_table num_nodes

      max_id = 0
      ivget(routing, :@buckets).each_with_index do |b, i|
        assert_equal max_id, b.left
        assert b.right > max_id
        max_id = b.right + 1
        assert_equal 2**Kademlia::ID_SIZE - 1, b.right if i == routing.buckets_count - 1
      end
    end
  end

  def test_neighbours
    routing = routing_table 1000

    1000.times do |i|
      node = random_node

      nearest_bucket = routing.buckets_by_distance(node)[0]
      next if nearest_bucket.empty?

      node_a = ivget(nearest_bucket, :@nodes)[0]
      node_b = fake_node_from_id node_a.id+1
      assert_equal node_a, routing.neighbours(node_b)[0]

      node_b = fake_node_from_id node_a.id-1
      assert_equal node_a, routing.neighbours(node_b)[0]
    end
  end

  def test_setup
    # nodes connect to any peer and do a lookup for themselves
    proto = get_wired_protocol
    wire = proto.wire
    other = routing_table

    # lookup self
    proto.bootstrap [other.node]
    msg = wire.poll other.node

    assert_equal [:find_node, proto.routing.node, proto.routing.node.id], msg
    assert_equal nil,  wire.poll(other.node)
    assert_equal [], wire.messages

    # respond with neighbours
    closest = other.neighbours(msg[2])
    assert_equal Kademlia::K, closest.size
    proto.recv_neighbours random_node, closest

    # expect A=3 lookups
    Kademlia::A.times do |i|
      msg = wire.poll closest[i]
      assert_equal [:find_node, proto.routing.node, proto.routing.node.id], msg
    end

    # and pings for all nodes
    closest.each do |node|
      msg = wire.poll node
      assert_equal :ping, msg[0]
    end

    # nothing else
    assert_equal [], wire.messages
  end

  def test_eviction
    proto = get_wired_protocol
    proto.instance_variable_set :@routing, routing_table
    wire = proto.wire

    node = proto.routing.neighbours(random_node)[0]
    proto.ping node
    msg = wire.poll(node)
    assert_equal :ping, msg[0]
    assert_equal [], wire.messages

    proto.recv_pong node, msg[2]
    assert_equal [], wire.messages
    assert proto.routing.include?(node)

    assert_equal node, proto.routing.bucket_by_node(node).tail
  end

  def test_eviction_node_active
    proto = get_wired_protocol
    routing = routing_table 10000 # set high, so add won't split
    proto.instance_variable_set :@routing, routing
    wire = proto.wire

    # get a full bucket
    full_buckets = ivget(routing, :@buckets).select {|b| b.full? && !b.should_split? }
    bucket = full_buckets[0]
    assert !bucket.should_split?
    assert_equal Kademlia::K, bucket.size

    bucket_nodes = bucket.to_a # bucket nodes copy
    eviction_candidate = bucket.head

    # create node to insert
    node = random_node
    node.instance_variable_set :@id, bucket.left+1
    assert bucket.in_range?(node)
    assert_equal bucket, routing.bucket_by_node(node)

    # insert node
    proto.update node

    # expect bucket not split
    assert Kademlia::K, bucket.size
    assert_equal bucket_nodes, bucket.to_a
    assert_equal eviction_candidate, bucket.head

    # expect node not to be in bucket yet
    assert !bucket.include?(node)
    assert !routing.include?(node)

    # expect a ping to bucket.head
    msg = wire.poll(eviction_candidate)
    assert_equal :ping, msg[0]
    assert_equal proto.node, msg[1]
    assert_equal 1, ivget(proto, :@expected_pongs).size

    expected_pingid = ivget(proto, :@expected_pongs).keys[0]
    assert_equal 96, expected_pingid.size

    echo = expected_pingid[0,32]
    assert_equal 32, echo.size
    assert_equal [], wire.messages

    # reply late
    sleep Kademlia::REQUEST_TIMEOUT
    proto.recv_pong eviction_candidate, echo

    # expect no other messages
    assert_equal [], wire.messages

    # expect node be added
    assert routing.include?(node)
    assert !routing.include?(eviction_candidate)
    assert_equal node, bucket.tail
    assert !ivget(bucket, :@replacement_cache).include?(eviction_candidate)
  end

  def test_eviction_node_split
    proto = get_wired_protocol
    routing = routing_table 1000 # set low, so we'll split
    proto.instance_variable_set :@routing, routing
    wire = proto.wire

    full_buckets = ivget(routing, :@buckets).select {|b| b.full? && b.should_split? }
    bucket = full_buckets[0]
    assert bucket.should_split?
    assert Kademlia::K, bucket.size

    bucket_nodes = bucket.to_a
    eviction_candidate = bucket.head

    node = random_node
    node.instance_variable_set :@id, bucket.left+1
    assert bucket.in_range?(node)
    assert_equal bucket, routing.bucket_by_node(node)

    proto.update node

    # bucket is splitted to two new bucket, but itself is not changed
    assert_equal bucket_nodes, bucket.to_a
    assert_equal eviction_candidate, bucket.head

    assert !bucket.include?(node)
    assert routing.include?(node)

    assert !wire.poll(eviction_candidate)
    assert_equal [], wire.messages

    assert routing.include?(node)
    assert_equal eviction_candidate, bucket.head
  end

  def test_ping_adds_sender
    proto = get_wired_protocol
    assert_equal 0, proto.routing.size

    10.times do |i|
      proto.recv_ping random_node, "some id #{i}"
      assert_equal i+1, proto.routing.size
    end
  ensure
    WireMock.reset
  end

  def test_two
    one = get_wired_protocol
    one.instance_variable_set :@routing, routing_table(100)
    two = get_wired_protocol
    wire = one.wire
    assert two.node != one.node

    two.ping one.node
    wire.process([one, two])

    # find :two on :one, because two has only :one in its routing table
    two.find_node two.node.id

    # :one replies with K neighbours to :two, because :one has a 100 nodes routing table
    # :two forward :find_node to the first A neighbours, then ping all neighbours
    wire.process([one, two], 2)
    assert wire.messages.size >= Kademlia::K

    msg = wire.messages.shift
    assert_equal :find_node, msg[1]

    wire.messages[Kademlia::A..-1].each do |m|
      assert_equal :ping, m[1]
    end
  ensure
    WireMock.reset
  end

  def test_many
    WireMock.reset

    num_nodes = 17
    assert num_nodes >= Kademlia::K+1

    protos = []
    num_nodes.times do |i|
      protos.push get_wired_protocol
    end

    bootstrap = protos[0]
    wire = bootstrap.wire

    # bootstrap
    # after this bootstrap node has all nodes in its routing table
    protos[1..-1].each do |p|
      p.bootstrap [bootstrap.node]
      wire.process protos
    end

    # now everybody does a find node to fill the buckets
    protos[1..-1].each do |p|
      p.find_node p.node.id # find_node to bootstrap node
      wire.process protos # can all send in parallel
    end

    protos.each_with_index do |p, i|
      assert p.routing.size >= Kademlia::K
    end
  end

  def test_find_closest
    WireMock.reset

    num_tests = 10
    num_nodes = 50

    protos = []
    num_nodes.times do |i|
      protos.push get_wired_protocol
    end

    bootstrap = protos[0]
    wire = bootstrap.wire

    # bootstrap
    # after this bootstrap node has all nodes in its routing table
    protos[1..-1].each do |p|
      p.bootstrap [bootstrap.node]
      wire.process protos
    end

    # now everybody does a find node to fill the buckets
    protos[1..-1].each do |p|
      p.find_node p.node.id # find_node to bootstrap node
      wire.process protos # can all send in parallel
    end

    all_nodes = protos.map(&:node)

    protos[0,num_tests].each_with_index do |p, i|
      all_nodes.each do |node, j|
        next if p.node == node
        p.find_node node.id
        p.wire.process protos
        assert_equal node, p.routing.neighbours(node)[0]
      end
    end
  end

  private

  def random_pubkey
    SecureRandom.random_bytes(Kademlia::PUBKEY_SIZE / 8)
  end

  def random_node
    Kademlia::Node.new random_pubkey
  end

  def routing_table(num_nodes=1000)
    node = random_node
    routing = Kademlia::RoutingTable.new node

    num_nodes.times do |i|
      routing.add random_node
      assert routing.buckets_count <= i + 2
    end

    assert routing.buckets_count <= 512
    routing
  end

  def fake_node_from_id(id)
    random_node.tap do |node|
      node.instance_variable_set :@id, id
    end
  end

  class WireMock < Kademlia::WireInterface
    @@messages = []

    def self.reset
      @@messages.clear
    end

    def initialize(sender)
      raise ArgumentError unless sender.is_a?(DEVp2p::Kademlia::Node)
      @sender = sender
      raise "messages must be empty" unless @@messages.empty?
    end

    def messages
      @@messages
    end

    def send_ping(node)
      echo = SecureRandom.hex(16)
      @@messages.push [node, :ping, @sender, echo]
      echo
    end

    def send_pong(node, echo)
      @@messages.push [node, :pong, @sender, echo]
    end

    def send_find_node(node, nodeid)
      @@messages.push [node, :find_node, @sender, nodeid]
    end

    def send_neighbours(node, neighbours)
      @@messages.push [node, 'neighbours', @sender, neighbours]
    end

    def poll(node)
      @@messages.each_with_index do |x, i|
        if x[0] == node
          @@messages.delete_at i
          return x[1..-1]
        end
      end

      nil
    end

    ##
    # process messages until none are left or if process steps messages if
    # steps > 0
    #
    def process(kademlia_protocols, steps=0)
      i = 0
      proto_by_node = kademlia_protocols.map {|p| [p.node, p] }.to_h

      while !@@messages.empty?
        msg = @@messages.shift
        raise 'expect Node' unless msg[2].is_a?(DEVp2p::Kademlia::Node)

        target = proto_by_node[msg[0]]
        cmd = "recv_#{msg[1]}"
        target.send cmd, *msg[2..-1]

        i += 1
        return if steps > 0 && i == steps
      end

      raise 'expect all messages be processed' unless @@messages.empty?
    end
  end

  def get_wired_protocol
    node = random_node
    Kademlia::Protocol.new node, WireMock.new(node)
  end

end
