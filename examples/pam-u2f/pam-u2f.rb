#!/usr/bin/env ruby
# Use with pam_exec(8)
require 'json'
require 'socket'
require 'syslog'
require 'uri'
require 'net/http'
require 'net/https'
require 'fileutils'
require 'digest/sha2'

class ClarionClient
  def initialize(endpoint)
    @endpoint = endpoint
  end

  def create_authn(keys, name: nil, comment: nil)
    clarion_keys = keys.map{ |_| {name: _[:name], handle: _[:handle], counter: _[:counter], public_key: _[:public_key] } }
    authn = post('/api/authn', name: name, comment: comment, keys: clarion_keys)
    authn['authn']
  end

  def get_authn(id)
    get("/api/authn/#{id}")['authn']
  end

  private

  def get(path)
    uri = URI.parse("#{@endpoint}#{path}")
    req = Net::HTTP::Get.new(uri.request_uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.start do
      resp = http.request(req).tap(&:value)
      JSON.parse(resp.body)
    end
  end


  def post(path, payload)
    uri = URI.parse("#{@endpoint}#{path}")
    req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    req.body = payload.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.start do
      resp = http.request(req).tap(&:value)
      JSON.parse(resp.body)
    end
  end
end

Syslog.open("pam-u2f")
$stdout.sync = true

CLARION_URL = ARGV[0]

mode = nil
mode = :initiate if ARGV.delete('--initiate')
mode = :wait if ARGV.delete('--wait')
unless mode and CLARION_URL
  abort "Usage: #{$0} {--wait|--initiate} [CLARION_URL]"
end

KEYS_DIR = '/var/cache/pam-u2f/users'
STATE_DIR = '/run/pam-u2f'

FileUtils.mkdir_p(STATE_DIR)

clarion = ClarionClient.new(CLARION_URL)

user = ENV.fetch('PAM_USER')
key_path = File.join(KEYS_DIR, user)
state_path = File.join(STATE_DIR, Digest::SHA256.hexdigest("#{user},#{ENV['PAM_RHOST']}"))

# Not using U2F, exit
unless File.exist?(key_path)
  exit 1
end

class HaveToRetry < Exception; end

begin
  keys = JSON.parse(File.read(key_path), symbolize_names: true)

  case mode
  when :initiate
    # Create clarion authn and present URL.
    File.open(state_path, File::RDWR|File::CREAT, 0600) do |io|
      # Reuse existing state if possible
      io.flock(File::LOCK_SH)
      io.rewind
      json = io.read
      state = begin
                JSON.parse(json, symbolize_names: true)
              rescue JSON::ParserError
                nil
              end

      authn = nil
      if state
        if !state.is_a?(Hash) || !state[:id]
          puts "PAM-U2F ERR: state file broken @ #{Socket.gethostname} #{state_path}"
          Syslog.err('%s', "Clarion Authn broken for #{user} #{ENV['PAM_RHOST']} : #{state_path}")
          raise "state is broken" 
        end

        # Check authn status (recorded in state).
        begin
          authn = clarion.get_authn(state[:id])

          # authn should be opened to reuse.
          if authn['status'] == 'open'
            id = authn['id']
            html_url = authn['html_url']
          else
            authn = nil
          end
        rescue Net::HTTPNotFound
          authn = nil
        end
      end

      unless authn
        io.flock(File::LOCK_EX)
        # Other process may remove a state file. If so, simply retry to create it again.
        raise HaveToRetry unless File.exist?(state_path)

        authn = clarion.create_authn(keys, name: user, comment: "SSH login #{ENV['PAM_RHOST']}")
        id = authn && authn['id']
        html_url = authn && authn['html_url']

        raise "failed to create authn" unless id && html_url
        io.rewind
        io.puts({user: user, rhost: ENV['PAM_RHOST'], id: id, html_url: html_url}.to_json)
        io.flush
        io.truncate(io.pos)
      end
      io.flock(File::LOCK_UN)

      Syslog.info('%s', "Clarion Authn created for #{user} #{ENV['PAM_RHOST']} : #{id.inspect}")
      puts "PAM-U2F: #{html_url}"
      puts
      puts "--- Send empty password ---"
    end
    exit 1
  when :wait
    unless File.exist?(state_path)
      puts "PAM-U2F ERR: state not exist @ #{Socket.gethostname} #{state_path}"
      Syslog.err("%s", "called without initiate, state not exists: #{user} #{ENV['PAM_RHOST']} #{state_path}")
      exit 1
    end
    File.open(state_path, 'r', 0600) do |io|
      io.flock(File::LOCK_SH)
      io.rewind
      state = JSON.parse(io.read, symbolize_names: true)
      id = state[:id]

      authn = nil
      loop do
        authn = clarion.get_authn(id)
        if authn['status'] != 'open'
          break
        end
        sleep 1
      end

      if authn['status'] == 'verified'
        key = keys.find { |_| _[:handle] == authn['verified_key']['handle'] }
        Syslog.info('%s', "Clarion Authn #{user} #{ENV['PAM_RHOST']} #{id.inspect} : status=#{authn['status']} verified_key=#{key[:name].inspect}")
        puts "PAM-U2F verified with key #{key[:name]}"
        puts
        io.flock(File::LOCK_EX)
        if File.exist?(state_path)
          File.unlink(state_path)
        end
        exit 0
      end
      Syslog.warning('%s', "Clarion Authn #{user} #{ENV['PAM_RHOST']} #{id.inspect} : status=#{authn['status']}")
      puts "PAM-U2F authn #{authn['status']} ..."
      puts
      File.unlink(state_path)
      exit 1
    end
  end
rescue HaveToRetry
  retry
rescue SystemExit
  raise
rescue Exception => e
  puts "PAM-U2F Error"
  Syslog.err('%s', "Err: #{e.inspect}\t#{e.backtrace.join("\t")}")
  File.unlink(state_path) if state_path && File.exist?(state_path)
  raise
end
# Fail safe
exit 1
