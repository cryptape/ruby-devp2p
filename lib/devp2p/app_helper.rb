# -*- encoding : ascii-8bit -*-

module DEVp2p
  class AppHelper

    def run(app_class, service_class, num_nodes: 3, seed: 0, min_peers: 2, max_peers: 2, random_port: false)
      base_port = random_port ? SecureRandom.random_number(50000) + 10000 : 29870

      bootstrap_node_privkey = Crypto.mk_privkey "#{seed}:udp:0"
      bootstrap_node_pubkey = Crypto.privtopub bootstrap_node_privkey
      enode = Utils.host_port_pubkey_to_uri "0.0.0.0", base_port, bootstrap_node_pubkey

      services = [Discovery::Transport, PeerManager]#, service_class]

      base_config = {}
      services.each {|s| Utils.update_config_with_defaults base_config, s.default_config }

      base_config[:discovery][:bootstrap_nodes] = [enode]
      base_config[:seed] = seed
      base_config[:base_port] = base_port
      base_config[:num_nodes] = num_nodes
      base_config[:min_peers] = min_peers
      base_config[:max_peers] = max_peers

      apps = []
      num_nodes.times do |node_num|
        app = create_app node_num, base_config, services, app_class
        apps.push app
      end

      serve_until_stopped apps
    end

    def create_app(node_num, config, services, app_class)
      num_nodes = config[:num_nodes]
      base_port = config[:base_port]
      seed = config[:seed]
      min_peers = config[:min_peers]
      max_peers = config[:max_peers]

      raise "invalid node_num" unless node_num < num_nodes
      #raise "invalid min/max peers" unless min_peers <= max_peers && max_peers < num_nodes

      config = Marshal.load Marshal.dump(config)
      config[:node_num] = node_num

      config[:node][:privkey_hex] = Utils.encode_hex Crypto.mk_privkey("#{seed}:udp:#{node_num}")
      config[:discovery][:listen_port] = base_port + node_num
      config[:p2p][:listen_port] = base_port + node_num
      config[:p2p][:min_peers] = [min_peers, 10].min
      config[:p2p][:max_peers] = max_peers
      config[:client_version_string] = "NODE#{node_num}"

      app = app_class.new config

      services.each do |service|
        raise "invalid service" unless service.instance_of?(Class) && service < BaseService

        if !app.config[:deactivated_services].include?(service.name)
          raise "service should not be active" if app.services.has_key?(service.name)
          service.register_with_app app
          raise "servier should be active" unless app.services.has_key?(service.name)
        end
      end

      app
    end

    def serve_until_stopped(apps)
      apps.each do |app|
        app.start

        if app.config[:post_app_start_callback]
          app.config[:post_app_start_callback].call(app)
        end
      end

      apps.each(&:join)

      # finally stop
      apps.each(&:stop)
    end

  end
end
