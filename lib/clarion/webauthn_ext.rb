require 'webauthn'

module WebAuthn
  class AuthenticatorData
    def sign_count
      # https://w3c.github.io/webauthn/#sec-authenticator-data
      @sign_count ||= data_at(RP_ID_HASH_LENGTH + FLAGS_LENGTH, SIGN_COUNT_LENGTH).unpack('L>')[0]
    end
  end

  class AuthenticatorAssertionResponse
    # For debug
    # def valid?(original_challenge, original_origin, allowed_credentials:)
    #   p({
    #     type: valid_type?,
    #     challenge: valid_challenge?(original_challenge),
    #     origin: valid_origin?(original_origin),
    #     rp_id: valid_rp_id?(original_origin),
    #     data_valid: authenticator_data.valid?,
    #     up: authenticator_data.user_present?,
    #     cred: valid_credential?(allowed_credentials),
    #     signature: valid_signature?(credential_public_key(allowed_credentials)),
    #   })

    #   valid_type? &&
    #     valid_challenge?(original_challenge) &&
    #     valid_origin?(original_origin) &&
    #     valid_rp_id?(original_origin) &&
    #     authenticator_data.valid? &&
    #     authenticator_data.user_present?
    #   valid_credential?(allowed_credentials) &&
    #     valid_signature?(credential_public_key(allowed_credentials))
    # end

    # To expose sign_count
    public :authenticator_data
  end

  class AuthenticatorAttestationResponse
    # To expose sign_count
    public :authenticator_data
  end

  class AuthenticatorResponse
    # Providing the proper origin name and RP ID is the application's responsibility. And, RP ID and client origin is different concept: https://w3c.github.io/webauthn/#api
    # There's no expectation of use of different RP ID which is separately from request origin, and appid extension.
    # https://w3c.github.io/webauthn/#sctn-appid-extension

    # https://github.com/cedarcode/webauthn-ruby/blob/85f69ddab4776851b8bbc53c1dfbaef87c0c24e9/lib/webauthn/authenticator_response.rb#L39
    # when appid extension is in use, rp_id_hash could be a digest of "https://host" but the original code always generating a digest of URI host.
    def valid_rp_id?(original_origin)
      OpenSSL::Digest::SHA256.digest(original_origin) == authenticator_data.rp_id_hash
    end

    # no existing good interface to inject RP ID and origin separately. We do proper validation on our side (authenticator.rb, registrator.rb)
    def valid_origin?(original_origin) 
      true
    end

    # To perform origin validation
    public :client_data
  end
end
