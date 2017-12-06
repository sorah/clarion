require 'erubis'
require 'sinatra/base'
require 'u2f'
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

      def u2f
        @u2f ||= U2F::U2F.new(conf.app_id || request.base_url)
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
            url: "#{request.base_url}/api/authn/#{authn.id}",
            html_url: "#{request.base_url}/authn/#{authn.id}",
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
      if @authn.verified?
        halt 410, "Authn already processed"
      end
      if @authn.expired?
        halt 410, "Authn expired"
      end


      authenticator = Authenticator.new(@authn, u2f, counter, store)
      @app_id, @requests, @challenge = authenticator.request

      @req_id = SecureRandom.urlsafe_base64(12)
      session[:reqs] ||= {}
      session[:reqs][@req_id] = {challenge: @challenge}

      erb :authn
    end

    ## API (returns user-facing UI)

    register = Proc.new do
      unless params[:name] && params[:callback] && params[:public_key]
        halt 400, 'missing params'
      end
      if params[:callback].start_with?('js:') && !(conf.registration_allowed_url === params[:callback])
        halt 400, 'invalid callback'
      end

      public_key = begin
        OpenSSL::PKey::RSA.new(params[:public_key].unpack('m*')[0], '')
      rescue OpenSSL::PKey::RSAError
        halt 400, 'invalid public key'
      end

      @reg_id = SecureRandom.urlsafe_base64(12)
      registrator = Registrator.new(u2f, counter)
      @app_id, @requests = registrator.request
      session[:regis] ||= []
      session[:regis] << {
        id: @reg_id,
        challenges: @requests.map(&:challenge),
        key: public_key.to_der,
      }
      session[:regis].shift(session[:regis].size - 4) if session[:regis].size > 4

      @callback = params[:callback]
      @state = params[:state]
      @name = params[:name]
      @comment = params[:comment]
      erb :register
    end
    get '/register', &register
    post '/register', &register

    ## Internal APIs (used from UI)

    post '/ui/register' do
      content_type :json
      unless data[:reg_id] && data[:response]
        halt 400, '{"error": "Missing params"}'
      end

      session[:regis] ||= []
      reg = session[:regis].find { |_| _[:id] == data[:reg_id] }
      unless reg && reg[:challenges] && reg[:key]
        halt 400, '{"error": "Invalid :reg"}'
      end

      public_key = begin
        OpenSSL::PKey::RSA.new(reg[:key], '') # der
      rescue OpenSSL::PKey::RSAError
        halt 400, '{"error": "Invalid public key"}'
      end

      registrator = Registrator.new(u2f, counter)
      key = registrator.register!(reg[:challenges], data[:response])
      key.name = data[:name]

      session[:regis].reject! { |_| _[:id] == data[:reg_id] }

      {ok: true, encrypted_key: key.to_encrypted_json(public_key, :all)}.to_json
    end

    post '/ui/verify/:id' do
      content_type :json
      unless data[:req_id] && data[:response]
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
      if @authn.verified?
        halt 410, '{"error": "authn already processed"}'
      end
      if @authn.expired?
        halt 410, '{"error": "authn expired"}'
      end

      authenticator = Authenticator.new(@authn, u2f, counter, store)

      begin
        authenticator.verify!(
          challenge,
          data[:response]
        )
      rescue U2F::Error => e
        halt 400, {error: "U2F Error: #{e.message}"}.to_json
      rescue Authenticator::InvalidKey => e
        halt 400, {error: "It is an unregistered key"}.to_json
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
      @register_url = "#{request.base_url}/register"
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
