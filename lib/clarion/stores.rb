require 'clarion/const_finder'

module Clarion
  module Stores
    def self.find(name)
      ConstFinder.find(self, 'clarion/stores', name)
    end
  end
end
