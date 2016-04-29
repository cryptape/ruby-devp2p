# -*- encoding : ascii-8bit -*-
require 'minitest/autorun'
require 'celluloid/test'
require 'devp2p'
#require 'pry-byebug'

Logging.logger.root.appenders = [
  Logging::Appenders.file(
    File.expand_path('../../test.log', __FILE__),
    layout: Logging.layouts.pattern.new(pattern: "%.1l, [%d] %5l -- %c: %m\n")
  ),
  #Logging.appenders.stdout
]
#Logging.logger.root.level = :debug

def ivget(obj, name)
  obj.instance_variable_get(name)
end
