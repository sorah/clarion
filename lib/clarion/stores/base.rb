module Clarion
  module Stores
    class Base
      def initialize(options={})
        @options = options
      end

      def store_authn(authn)
        raise NotImplementedError
      end

      def find_authn(id)
        raise NotImplementedError
      end
    end
  end
end
