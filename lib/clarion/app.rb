require 'erubis'
require 'sinatra/base'
require 'securerandom'

require 'clarion/registrator'
require 'clarion/authenticator'
require 'clarion/authn'

module Clarion
  def self.app(*args)
    App.rack(*args)
  end

  class App < Sinatra::Base
    CONTEXT_RACK_ENV_NAME = 'clarion.ctx'

    def self.initialize_context(config)
      {
        config: config,
      }
    end

    def self.rack(config={})
      klass = App

      context = initialize_context(config)
      lambda { |env|
        env[CONTEXT_RACK_ENV_NAME] = context
        klass.call(env)
      }
    end

    configure do
      enable :logging
    end

    set :root, File.expand_path(File.join(__dir__, '..', '..', 'app'))
    set :erb, :escape_html => true

    helpers do
      def data
        begin
          @data = JSON.parse(request.body.tap(&:rewind).read, symbolize_names: true)
        rescue JSON::ParserError
          content_type :json
          halt 400, '{"error": "invalid_payload"}'
        end
      end

      def context
        request.env[CONTEXT_RACK_ENV_NAME]
      end

      def conf
        context[:config]
      end

      def base_url
        conf.app_id || request.base_url
      end

      def rp_id
        conf.rp_id || request.host
      end

      def legacy_app_id
        base_url
      end

      def counter
        conf.counter
      end

      def store
        conf.store
      end

      def render_authn_json(authn)
        {
          authn: authn.as_json.merge(
            url: "#{base_url}/api/authn/#{authn.id}",
            html_url: "#{base_url}/authn/#{authn.id}",
          )
        }.to_json
      end
    end

    ## UI

    get '/' do
      content_type :text
      "Clarion\n"
    end

    get '/authn/:id' do
      @authn = store.find_authn(params[:id])
      unless @authn
        halt 404, "authn not found"
      end
      if @authn.expired?
        halt 410, "Authn expired"
      end
      if @authn.closed?
        halt 410, "Authn already processed"
      end

      authenticator = Authenticator.new(@authn, counter, store, rp_id: rp_id, legacy_app_id: legacy_app_id)
      @credential_request_options = authenticator.credential_request_options

      @req_id = SecureRandom.urlsafe_base64(12)
      session[:reqs] ||= {}
      session[:reqs][@req_id] = {challenge: authenticator.challenge}

      erb :authn
    end

    ## API (returns user-facing UI)

    register = Proc.new do
      unless params[:name] && params[:callback] && params[:public_key]
        halt 400, 'missing params'
      end
      if params[:callback].start_with?('js:')
        unless conf.registration_allowed_url === params[:callback][3..-1]
          halt 400, 'invalid callback'
        end
      else
        unless conf.registration_allowed_url === params[:callback]
          halt 400, 'invalid callback'
        end
      end

      public_key = begin
        OpenSSL::PKey::RSA.new(params[:public_key].unpack('m*')[0], '')
      rescue OpenSSL::PKey::RSAError
        halt 400, 'invalid public key'
      end

      @reg_id = SecureRandom.urlsafe_base64(12)
      @name = params[:name]
      # TODO: Give proper user_handle
      registrator = Registrator.new(counter, rp_id: rp_id, rp_name: "Clarion: #{request.host}", display_name: @name)
      @credential_creation_options = registrator.credential_creation_options

      session[:regis] ||= []
      session[:regis] << {
        id: @reg_id,
        challenge: registrator.challenge,
        user_handle: registrator.user_handle,
        key: public_key.to_der,
      }
      session[:regis].shift(session[:regis].size - 4) if session[:regis].size > 4

      @callback = params[:callback]
      @state = params[:state]
      @comment = params[:comment]
      erb :register
    end
    get '/register', &register
    post '/register', &register

    ## Internal APIs (used from UI)

    post '/ui/register' do
      content_type :json
      unless data[:reg_id] && data[:attestation_object] && data[:client_data_json]
        halt 400, '{"error": "Missing params"}'
      end

      session[:regis] ||= []
      reg = session[:regis].find { |_| _[:id] == data[:reg_id] }
      unless reg && reg[:challenge] && reg[:user_handle] && reg[:key]
        halt 400, '{"error": "Invalid :reg"}'
      end

      public_key = begin
        OpenSSL::PKey::RSA.new(reg[:key], '') # der
      rescue OpenSSL::PKey::RSAError
        halt 400, '{"error": "Invalid public key"}'
      end

      registrator = Registrator.new(counter, rp_id: rp_id, user_handle: reg[:user_handle])
      begin
        key = registrator.register!(
          challenge: reg[:challenge],
          origin: request.base_url,
          attestation_object: data[:attestation_object].unpack('m*')[0],
          client_data_json: data[:client_data_json].unpack('m*')[0],
        )
      rescue Registrator::InvalidAttestation => e
        logger.warn "invalid attestation error: #{e.inspect}"
        halt 400, {user_error: true, error: "Invalid attestation"}.to_json
      end
      key.name = data[:name]

      session[:regis].reject! { |_| _[:id] == data[:reg_id] }

      {ok: true, name: key.name, encrypted_key: key.to_encrypted_json(public_key, :all)}.to_json
    end

    post '/ui/cancel/:id' do
      content_type :json
      unless data[:req_id]
        halt 400, '{"error": "missing params"}'
      end
      session[:reqs] ||= {}
      unless session[:reqs][data[:req_id]]
        halt 400, '{"error": "invalid :req_id"}'
      end
      challenge = session[:reqs][data[:req_id]][:challenge]
      unless challenge
        halt 400, '{"error": "invalid :req_id"}'
      end

      @authn = store.find_authn(params[:id])
      unless @authn
        halt 404, '{"error": "authn not found"}'
      end
      if @authn.expired?
        halt 410, '{"error": "authn expired"}'
      end
      if @authn.closed?
        halt 410, '{"error": "authn already processed"}'
      end

      @authn.cancel!
      store.store_authn(@authn)
      session[:reqs].delete data[:req_id]

      '{"ok": true}'
    end

    post '/ui/verify/:id' do
      content_type :json
      unless data[:req_id] && data[:authenticator_data] && data[:client_data_json] && data[:signature] && data[:credential_id]
        halt 400, '{"error": "missing params"}'
      end
      session[:reqs] ||= {}
      unless session[:reqs][data[:req_id]]
        halt 400, '{"error": "invalid :req_id"}'
      end
      challenge = session[:reqs][data[:req_id]][:challenge]
      unless challenge
        halt 400, '{"error": "invalid :req_id"}'
      end

      @authn = store.find_authn(params[:id])
      unless @authn
        halt 404, '{"error": "authn not found"}'
      end
      if @authn.expired?
        halt 410, '{"error": "authn expired"}'
      end
      if @authn.closed?
        halt 410, '{"error": "authn already processed"}'
      end

      authenticator = Authenticator.new(@authn, counter, store, rp_id: rp_id, legacy_app_id: legacy_app_id)

      begin
        authenticator.verify!(
          challenge: challenge,
          origin: request.base_url,
          credential_id: data[:credential_id],
          authenticator_data: data[:authenticator_data].unpack('m*')[0],
          client_data_json: data[:client_data_json].unpack('m*')[0],
          signature: data[:signature].unpack('m*')[0],
        )
        logger.info "authn verified (#{@authn.id}) with credential_id=#{data[:credential_id]}"
      rescue Authenticator::InvalidAssertion => e
        logger.warn "authn verify error (#{@authn.id}; credential_id=#{data[:credential_id]}): #{e.inspect}"
        halt 400, {user_error: true, error: "Invalid assertion"}.to_json
      rescue Authenticator::InvalidKey => e
        logger.warn "authn verify error (#{@authn.id}; credential_id=#{data[:credential_id]}): #{e.inspect}"
        halt 401, {user_error: true, error: "It is an unregistered key"}.to_json
      end

      session[:reqs].delete data[:req_id]
      '{"ok": true}'
    end

    ## API

    post '/api/authn' do
      content_type :json
      @authn = begin
        Authn.make(
          name: data[:name],
          comment: data[:comment],
          keys: data[:keys],
          expires_at: Time.now + conf.authn_default_expires_in,
          status: :open,
        )
      rescue ArgumentError
        halt 400, '{"error": "invalid params"}'
      end
      store.store_authn(@authn)
      render_authn_json @authn
    end

    get '/api/authn/:id' do
      content_type :json
      @authn = store.find_authn(params[:id])
      unless @authn
        halt 404, '{"error": "authn not found"}'
      end
      render_authn_json @authn
    end

    ## Testing purpose
    
    get '/test' do
      key = conf.options[:register_test_key] ||= OpenSSL::PKey::RSA.generate(2048)
      @name = 'testuser'
      @comment = 'test comment'
      @register_url = "#{base_url}/register"
      @callback =  "#{request.base_url}/test/callback"
      @public_key = [key.public_key.to_der].pack('m*').gsub(/\r?\n/, '')
      @state = SecureRandom.urlsafe_base64(12)
      erb :test
    end

    post '/test/callback' do
      key = conf.options[:register_test_key] ||= OpenSSL::PKey::RSA.generate(2048)
      if params[:data]
        @state = params[:state]
        json = params[:data]
        @key = Key.from_encrypted_json(key, json)
      elsif params[:key]
        @state = 'dummy'
        @key = Key.new(**JSON.parse(params[:key], symbolize_names))
      else
        halt 400, "what?"
      end
      erb :test_callback
    end
  end
end
