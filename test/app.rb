$:.unshift File.expand_path('../../lib', __FILE__)

require 'yaml'
require 'hashie'
require 'devp2p'

default_config = <<-EOF
discovery:
    bootstrap_nodes:
        # local bootstrap
        # - enode://6ed2fecb28ff17dec8647f08aa4368b57790000e0e9b33a7b91f32c41b6ca9ba21600e9a8c44248ce63a71544388c6745fa291f88f8b81e109ba3da11f7b41b9@127.0.0.1:30303
        # go_bootstrap
        #- enode://6cdd090303f394a1cac34ecc9f7cda18127eafa2a3a06de39f6d920b0e583e062a7362097c7c65ee490a758b442acd5c80c6fce4b148c6a391e946b45131365b@54.169.166.226:30303
        # cpp_bootstrap
        #- enode://4a44599974518ea5b0f14c31c4463692ac0329cb84851f3435e6d1b18ee4eae4aa495f846a0fa1219bd58035671881d44423876e57db2abd57254d0197da0ebe@5.1.83.226:30303
        # go1_bootstrap <- use this
        - enode://a979fb575495b8d6db44f750317d0f4622bf4c2aa3365d6af7c284339968eef29b69ad0dce72a4d8db5ebb4968de0e3bec910127f134779fbcb0cb6d3331163c@52.16.188.185:30303
        # go2_bootstrap
        #- enode://de471bccee3d042261d52e9bff31458daecc406142b401d4cd848f677479f73104b9fdeb090af9583d3391b7f10cb2ba9e26865dd5fca4fcdc0fb1e3b723c786@54.94.239.50:30303
        # python_bootstrap
        #- enode://2676755dd8477ad3beea32b4e5a144fa10444b70dfa3e05effb0fdfa75683ebd4f75709e1f8126cb5317c5a35cae823d503744e790a3a038ae5dd60f51ee9101@144.76.62.101:30303

p2p:
    num_peers: 10
    listen_host: 0.0.0.0
    listen_port: 13333

discovery:
    listen_host: 0.0.0.0
    listen_port: 13333
    bootstrap_nodes:
        # my node
        - enode://a255fad01ada3d61bbd07dba21fbb165eb073f8f7ae7ec6381ed6b9a382833278333335b5934f3282b28eb9d44e39c5244a2aec75c9b48ea0e4b57219cf36d85@127.0.0.1:30303

node:
    privkey_hex: 65462b0520ef7d3df61b9992ed3bea0c56ead753be7c8b3614e0ce01e4cac41b
EOF

include DEVp2p

if ARGV.size > 0
  puts "loading config from #{ARGV[0]}"
  config = Hashie::Mash.new YAML.load_file(ARGV[0])
else
  config = Hashie::Mash.new YAML.load(default_config)
  pubkey = Crypto.privtopub Utils.decode_hex(config['node']['privkey_hex'])
  config.node.id = Crypto.keccak256 pubkey
end

Logging.logger.root.level = :debug

Celluloid.boot

app = BaseApp.new config
Discovery::Transport.register_with_app app
PeerManager.register_with_app app

puts "application config:"
p app.config.to_h

app.start
app.join

#app.stop

