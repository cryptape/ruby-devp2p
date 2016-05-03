# ruby-devp2p

[![MIT License](https://img.shields.io/packagist/l/doctrine/orm.svg)](LICENSE)
[![travis build status](https://travis-ci.org/janx/ruby-devp2p.svg?branch=master)](https://travis-ci.org/janx/ruby-devp2p)

A ruby implementation of Ethereum's DEVp2p framework.

## Fiber Stack Size

DEVp2p is build on [Celluloid](https://github.com/celluloid/celluloid/), which
uses fibers to schedule tasks. Ruby's default limit on fiber stack size is quite
small, which need to be increased by setting environment variables:

```
export RUBY_FIBER_VM_STACK_SIZE=104857600 # 100MB
export RUBY_FIBER_MACHINE_STACK_SIZE=1048576000
```

## Resources

* [DEVp2p Whitepaper](https://github.com/ethereum/wiki/wiki/libp2p-Whitepaper)
* [RLPx](https://github.com/ethereum/devp2p/blob/master/rlpx.md)
