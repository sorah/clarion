module Clarion
  class Key
    CIPHER_ALGO = 'aes-256-gcm'
    def self.from_encrypted_json(private_key, json)
      payload = JSON.parse(json, symbolize_names: true)
      encrypted_data = payload.fetch(:data).unpack('m*')[0]
      encrypted_shared_key = payload.fetch(:key).unpack('m*')[0]

      shared_key_json = private_key.private_decrypt(encrypted_shared_key, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      shared_key_info = JSON.parse(shared_key_json, symbolize_names: true)
      iv = shared_key_info.fetch(:iv).unpack('m*')[0]
      shared_key = shared_key_info.fetch(:key).unpack('m*')[0]
      tag = shared_key_info.fetch(:tag).unpack('m*')[0]

      cipher = OpenSSL::Cipher.new(CIPHER_ALGO).tap do |c|
          c.decrypt
          c.key = shared_key
          c.iv = iv
          c.auth_data = ''
          c.auth_tag = tag
      end

      key_json = cipher.update(encrypted_data)
      key_json << cipher.final
      key = JSON.parse(key_json, symbolize_names: true)
      new(**key)
    end

    def initialize(handle:, type: 'fido-legacy', name: nil, public_key: nil, counter: nil)
      @type = type
      @handle = handle
      @name = name
      @public_key = public_key
      @counter = counter
    end

    attr_reader :type, :handle, :public_key
    attr_accessor :counter, :name

    def to_h(all=false)
      {
        type: type,
        handle: handle,
      }.tap do |h|
        h[:name] = name if name
        h[:counter] = counter if counter
        if all
          h[:public_key] = public_key if public_key
        end
      end
    end

    def public_key_bytes
      public_key.unpack('m*')[0]
    end

    def to_json(*args)
      to_h(*args).to_json
    end

    def to_encrypted_json(public_key, *args)
      cipher = OpenSSL::Cipher.new(CIPHER_ALGO)
      shared_key = OpenSSL::Random.random_bytes(cipher.key_len)
      cipher.encrypt
      cipher.key = shared_key
      cipher.iv = iv = cipher.random_iv
      cipher.auth_data = ''

      json = to_json(*args)

      ciphertext = cipher.update(json)
      ciphertext << cipher.final

      encrypted_key = public_key.public_encrypt({
        iv: [iv].pack('m*').gsub(/\r?\n/,''),
        tag: [cipher.auth_tag].pack('m*').gsub(/\r?\n/,''),
        key: [shared_key].pack('m*').gsub(/\r?\n/,''),
      }.to_json, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      {data: [ciphertext].pack('m*'), key: [encrypted_key].pack('m*')}.to_json
    end
  end
end
