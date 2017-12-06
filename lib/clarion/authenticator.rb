require 'base64'
require 'u2f'

module Clarion
  class Authenticator
    class Error < StandardError; end
    class InvalidKey < Error; end

    def initialize(authn, u2f, counter, store)
      @authn = authn
      @u2f = u2f
      @counter = counter
      @store = store
    end

    attr_reader :authn, :u2f, :counter, :store

    def request
      [u2f.app_id, u2f.authentication_requests(authn.keys.map(&:handle)), u2f.challenge]
    end

    def verify!(challenge, response_json)
      response = U2F::SignResponse.load_from_json(response_json)
      key = authn.key_for_handle(response.key_handle)
      unless key
        raise InvalidKey, "#{response.key_handle.inspect} is invalid token for authn #{authn.id}"
      end
      count = counter ? counter.get(key) : 0

      u2f.authenticate!(
        challenge,
        response,
        Base64.decode64(key.public_key),
        count,
      )

      unless authn.verify(key)
        raise Authenticator::InvalidKey
      end

      key.counter = response.counter
      if counter
        counter.store(key)
      end

      store.store_authn(authn)

      true
    end
  end
end
