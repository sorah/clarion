require 'clarion/key'

module Clarion
  class Registrator
    def initialize(u2f, counter)
      @u2f = u2f
      @counter = counter
    end

    attr_reader :u2f, :counter

    def request
      [u2f.app_id, u2f.registration_requests]
    end

    def register!(challenges, response_json)
      response = U2F::RegisterResponse.load_from_json(response_json)
      reg = u2f.register!(challenges, response)
      key = Key.new(handle: reg.key_handle, public_key: reg.public_key, counter: reg.counter)
      if counter
        counter.store(key)
      end
      key
    end
  end
end
