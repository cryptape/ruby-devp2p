# -*- encoding : ascii-8bit -*-
module DEVp2p
  VERSION = '0.0.1'

  VersionString = begin
                    git_describe_re = /^(?<version>v\d+\.\d+\.\d+)-(?<git>\d+-g[a-fA-F0-9]+(?:-dirty)?)$/

                    rev = `git describe --tags --dirty`
                    m = rev.match git_describe_re

                    ver = m ? "#{m[:version]}+git-#{m[:git]}" : VERSION
                  end
end
