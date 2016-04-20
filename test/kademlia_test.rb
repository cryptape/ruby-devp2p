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

end
