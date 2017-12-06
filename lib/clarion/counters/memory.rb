require 'thread'
require 'clarion/counters/base'

module Clarion
  module Counters
    class Memory < Base
      def initialize(*)
        super
        @lock = Mutex.new
        @counters = {}
      end

      def get(key)
        @lock.synchronize do
          @counters[key.handle]
        end
      end

      def store(key)
        @lock.synchronize do
          counter = @counters[key.handle]
          if !counter || key.counter > counter
            @counters[key.handle] = key.counter
          end
        end
      end
    end
  end
end
