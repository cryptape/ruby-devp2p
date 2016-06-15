# -*- encoding : ascii-8bit -*-
##
# # Node Discovery Protocol
#
# * [Node] - an entity on the network
# * [Node] ID - 512 bit public key of node
#
# The Node Discovery protocol provides a way to find RLPx nodes that can be
# connected to. It uses a Kademlia-like protocol to maintain a distributed
# database of the IDs and endpoints of all listening nodes.
#
# Each node keeps a node table as described in the Kademlia paper (Maymounkov,
# Mazières 2002). The node table is configured with a bucket size of 16
# (denoted `k` in Kademlia), concurrency of 3 (denoted `α` in Kademlia), and 8
# bits per hop (denoted `b` in Kademlia) for routing. The eviction check
# interval is 75 milliseconds, and the idle bucket-refresh interval is 3600
# seconds.
#
# In order to maintain a well-formed network, RLPx nodes should try to connect
# to an unspecified number of close nodes. To increase resilience against Sybil
# attacks, nodes should also connect to randomly chosen, non-close nodes.
#
# Each node runs the UDP-based RPC protocol defined below. The `FIND_DATA` and
# `STORE` requests from the Kademlia paper are not part of the protocol since
# the Node Discovery Protocol does not provide DHT functionality.
#
# ## Joining the network
#
# When joining the network, fills its node table by performing a recursive Find
# Node operation with its own ID as the 'Target'. The initial Find Node request
# is sent to one or more bootstrap nodes.
#
# ## RPC Protocol
#
# RLPx nodes that want to accept incoming connections should listen on the same
# port number for UDP packets (Node Discovery Protocol) and TCP connections
# (RLPx protocol).
#
# All requests time out after 300ms. Requests are not re-sent.
#
# ## Packet Data
#
# All packets contain an `Expiration` date to guard against replay attacks. The
# date should be interpreted as a UNIX timestamp. The receiver should discard
# any packet whose `Expiration` value is in the past.
#
# ### Ping (type 0x01)
#
# Ping packets can be sent and received at any time. The receiver should reply
# with a Pong packet and update the IP/Port of the sender in its node table.
#
#   PingNode packet-type: 0x01
#
#   struct PingNode         <= 59 bytes
#   {
#     h256 version = 0x3;   <= 1
#     Endpoint from;        <= 23
#     Endpoint to;          <= 23
#     unsigned expiration;  <= 9
#   }
#
#   struct Endpoint         <= 24 = [17,3,3]
#   {
#     unsigned address; // BE encoded 32-bit or 128-bit unsigned (layer3 address; size determins ipv4 vs ipv6)
#     unsigned udpPort; // BE encoded 16-bit unsigned
#     unsigned tcpPort; // BE encoded 16-bit unsigned
#   }
#
# ### Pong (type 0x02)
#
# Pong is the reply to a Ping packet.
#
#   Pong packet-type: 0x02
#
#   struct Pong             <= 66 bytes
#   {
#     Endpoint to;
#     h256 echo;
#     unsigned expiration;
#   }
#
# ### Find Node (type 0x03)
#
# Find Node packets are sent to locate nodes close to a given target ID. The
# receiver should reply with a Neighbours packet containing the `k` nodes
# closest to target that it knows about.
#
#   FindNode packet-type: 0x03
#
#   struct FindNode         <= 76 bytes
#   {
#     NodeId target; // Id of a node. The responding node will send back nodes closest to the target.
#     unsigned expiration;
#   }
#
# ### Neighbours (type 0x04)
#
# Neighbours is the reply to Find Node. It contains up to `k` nodes that the
# sender knows which are closest to the requested 'Target`.
#
#   Neighbours packet-type: 0x04
#
#   struct Neighbours        <= 1423
#   {
#     list nodes: struct Neighbours    <= 88...1411; 76...1219
#     {
#       inline Endpoint endpoint;
#       NodeId node;
#     };
#     unsigned expiration;
#   }
#

require 'devp2p/discovery/address'
require 'devp2p/discovery/node'
require 'devp2p/discovery/kademlia_protocol_adapter'
require 'devp2p/discovery/protocol'
require 'devp2p/discovery/service'
