# -*- encoding : ascii-8bit -*-

module DEVp2p

  class PeerErrorsBase

    def add(address, error, client_version='')
      raise NotImplemented
    end

  end

  class PeerErrors < PeerErrorsBase

    def initialize
      @errors = Hash.new {|h, k| h[k] = [] } # node:['error']
      @client_versions = {} # address: client_version

      at_exit do
        @errors.each do |k, v|
          puts "#{k} #{@client_versions.fetch(k, '')}"
          puts v.join("\t")
        end
      end
    end

    def add(address, error, client_version='')
      @errors[address].push error
      @client_versions[address] = client_version unless client_version.nil? || client_version.empty?
    end

  end

end

