require 'thread'
require 'clarion/stores/base'
require 'clarion/authn'

module Clarion
  module Stores
    class Memory < Base
      def initialize(*)
        super
        @lock = Mutex.new
        @store = {}
      end

      def store_authn(authn)
        @lock.synchronize do
          @store[authn.id] = authn.to_h(:all)
        end
      end

      def find_authn(id)
        @lock.synchronize do
          unless @store.key?(id)
            return nil
          end
          Authn.new(**@store[id])
        end
      end
    end
  end
end
