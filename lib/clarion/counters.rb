require 'clarion/const_finder'

module Clarion
  module Counters
    def self.find(name)
      ConstFinder.find(self, 'clarion/counters', name)
    end
  end
end
