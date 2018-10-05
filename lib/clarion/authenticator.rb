require 'base64'
require 'webauthn'
require 'securerandom'
require 'base64'

module Clarion
  class Authenticator
    class Error < StandardError; end
    class InvalidKey < Error; end
    class InvalidAssertion < Error; end

    def initialize(authn, counter, store, rp_id: nil, legacy_app_id: nil)
      @authn = authn
      @counter = counter
      @store = store
      @rp_id = rp_id
      @legacy_app_id = legacy_app_id
    end

    attr_reader :authn, :counter, :store, :rp_id, :legacy_app_id

    def challenge
      @challenge ||= SecureRandom.random_bytes(32)
    end

    def webauthn_request_extensions
      {}.tap do |e|
        e[:appid] = legacy_app_id if legacy_app_id
      end
    end

    def credential_request_options
      {
        publicKey: {
          timeout: 60000,
          # Convert to ArrayBuffer in sign.js
          challenge: challenge.each_byte.map(&:ord),
          allowCredentials: authn.keys.map { |_| {type: 'public-key', id: Base64.urlsafe_decode64(_.handle).each_byte.map(&:ord)} },
          extensions: webauthn_request_extensions,
        }
      }
    end

    def verify!(challenge: self.challenge(), origin:, extension_results: {}, credential_id:, authenticator_data:, client_data_json:, signature:)
      assertion = WebAuthn::AuthenticatorAssertionResponse.new(
        credential_id: credential_id,
        authenticator_data: authenticator_data,
        client_data_json: client_data_json,
        signature: signature,
      )

      key = authn.verify_by_handle(credential_id)
      unless key
        raise Authenticator::InvalidKey
      end

      rp_id = extension_results&.fetch('appid', false) ? legacy_app_id : self.rp_id()
      allowed_credentials = authn.keys.map { |_|  {id: _.handle, public_key: _.public_key_bytes} }
      unless assertion.valid?(challenge, origin, rp_id: rp_id, allowed_credentials: allowed_credentials)
        raise Authenticator::InvalidAssertion, "invalid assertion"
      end

      sign_count = assertion.authenticator_data.sign_count
      last_sign_count = counter ? counter.get(key) : 0

      if sign_count <= last_sign_count
        raise Authenticator::InvalidAssertion, "sign_count is decreased"
      end

      key.counter = sign_count

      counter.store(key) if counter
      store.store_authn(authn)
      true
    end
  end
end
