require 'bundler/setup'
require 'securerandom'

require 'clarion'

if ENV['RACK_ENV'] == 'production'
  raise 'Set $SECRET_KEY_BASE' unless ENV['SECRET_KEY_BASE']
end

if ENV['CLARION_DEV_HTTPS']
  use(Class.new do
    def initialize(app)
      @app = app
    end
    def call(env)
      @app.call env.merge('HTTPS' => 'on')
    end
  end)
end

config = {
  registration_allowed_url: Regexp.new(ENV.fetch('CLARION_REGISTRATION_ALLOWED_URL')),
  authn_default_expires_in: ENV.fetch('CLARION_AUTHN_DEFAULT_EXPIRES_IN', 300).to_i,
}

case ENV.fetch('CLARION_STORE', 's3')
when 's3'
  config[:store] = {
    kind: :s3,
    region: ENV.fetch('CLARION_STORE_S3_REGION'),
    bucket: ENV.fetch('CLARION_STORE_S3_BUCKET'),
    prefix: ENV.fetch('CLARION_STORE_S3_PREFIX'),
  }
when 'memory'
  config[:store] = {kind: :memory}
else
  raise ArgumentError, "Unsupported $CLARION_STORE"
end

case ENV.fetch('CLARION_COUNTER', nil)
when 'dynamodb'
  config[:counter] = {
    kind: :dynamodb,
    region: ENV.fetch('CLARION_COUNTER_DYNAMODB_REGION'),
    table_name: ENV.fetch('CLARION_COUNTER_DYNAMODB_TABLE'),
  }
when 'memory'
  config[:counter] = {kind: :memory}
when nil
  # do nothing
else
  raise ArgumentError, "Unsupported $CLARION_COUNTER"
end

use(
  Rack::Session::Cookie,
  key: 'clarionsess',
  expire_after: 3600,
  secure: ENV['RACK_ENV'] == 'production',
  secret: ENV.fetch('SECRET_KEY_BASE', SecureRandom.base64(256)),
)

run Clarion.app(Clarion::Config.new(config))
