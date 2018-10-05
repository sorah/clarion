require 'clarion/key'
require 'webauthn'
require 'securerandom'
require 'base64'

module Clarion
  class Registrator
    class Error < StandardError; end
    class InvalidAttestation < Error; end

    def initialize(counter, rp_name: 'clarion', rp_id:, user_handle: SecureRandom.base64(64), user_name: 'clarion user', display_name: user_name)
      @counter = counter
      @rp_id = rp_id
      @rp_name = rp_name
      @user_handle = user_handle
      @user_name = user_name
      @display_name = display_name
    end

    attr_reader :counter, :rp_id, :rp_name, :user_handle, :user_name, :display_name

    def challenge
      @challenge ||= SecureRandom.random_bytes(32)
    end

    def credential_creation_options
      {
        publicKey: {
          timeout: 60000,
          # Convert to ArrayBuffer in register.js
          challenge: challenge.each_byte.map(&:ord),
          attestation: 'none',
          pubKeyCredParams: [WebAuthn::CRED_PARAM_ES256],
          rp: {
            name: rp_name,
          },
          user: {
            id: Base64.decode64(user_handle).each_byte.map(&:ord),
            displayName: display_name,
            name: user_name,
          },
        },
      }
    end


    def register!(challenge: self.challenge(), origin:, attestation_object:, client_data_json:)
      attestation = WebAuthn::AuthenticatorAttestationResponse.new(
        attestation_object: attestation_object,
        client_data_json: client_data_json
      )

      unless attestation.valid?(challenge, origin, rp_id: rp_id)
        raise InvalidAttestation, "invalid attestation"
      end

      key = Key.new(
        type: 'webauthn',
        handle: Base64.urlsafe_encode64(attestation.credential.id).gsub(/\r?\n|=+/,''),
        user_handle: user_handle,
        public_key: Base64.encode64(attestation.credential.public_key).gsub(/\r?\n/,''),
        counter: attestation.authenticator_data.sign_count,
      )
      if counter
        counter.store(key)
      end
      key
    end
  end
end
