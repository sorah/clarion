#!/usr/bin/env ruby
require 'bundler/setup'
require 'webrick'
require 'webrick/ssl'
require 'logger'
require 'rack'
ENV['RACK_ENV'] = 'development'
ENV['CLARION_DEV_HTTPS']='1'
ENV['CLARION_REGISTRATION_ALLOWED_URL']='.+'

ENV['CLARION_STORE']='memory'
ENV['CLARION_COUNTER']='memory'


app, _ = Rack::Builder.parse_file(File.join(__dir__, 'config.ru'))

rack_options = {
  app: app,
  Port: ENV.fetch('PORT', 3000).to_i,
  Host: ENV.fetch('BIND', '127.0.0.1'),
  environment: 'development',
  server: 'webrick',
  Logger: Logger.new($stdout),#.tap { |_|  _.level = Logger::DEBUG },
  SSLEnable: true,
  SSLCertName: 'CN=localhost',
  SSLCertComment: 'dummy',
  SSLStartImmediately: true,
}
server = Rack::Server.new(rack_options)
server.start
