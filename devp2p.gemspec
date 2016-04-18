$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "devp2p/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "devp2p"
  s.version     = DEVp2p::VERSION
  s.authors     = ["Jan Xie"]
  s.email       = ["jan.h.xie@gmail.com"]
  s.homepage    = "https://github.com/janx/ruby-devp2p"
  s.summary     = "A ruby implementation of Ethereum's DEVp2p framework."
  s.description = "DEVp2p aims to provide a lightweight abstraction layer that provides these low-level algorithms, protocols and services in a transparent framework without predetermining the eventual transmission-use-cases of the protocols."
  s.license     = 'MIT'

  s.files = Dir["{lib}/**/*"] + ["LICENSE", "README.md"]

  s.add_dependency('hashie', ['~> 3.4'])
  s.add_dependency('block_logger', ['~> 0.1'])
  s.add_dependency('celluloid', ['~> 0.17'])
  s.add_dependency('digest-sha3', ['~> 1.1'])
  s.add_dependency('bitcoin-secp256k1', ['~> 0.3'])
  s.add_dependency('rlp', ['>= 0.7.1'])

  s.add_development_dependency('rake', ['~> 10.5'])
  s.add_development_dependency('minitest', '5.8.3')
  s.add_development_dependency('yard', '0.8.7.6')
end
