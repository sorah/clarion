module Clarion
  module Counters
    class Base
      def initialize(options={})
        @options = options
      end

      def get(key)
        raise NotImplementedError
      end

      def store(key)
        raise NotImplementedError
      end
    end
  end
end
