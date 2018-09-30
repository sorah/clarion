require 'clarion/stores'
require 'clarion/counters'

module Clarion
  class Config
    class << self
      def option(meth)
        options << meth
      end

      def options
        @options ||= []
      end
    end

    def initialize(options={})
      @options = options

      # Validation
      self.class.options.each do |m|
        send(m)
      end
    end

    attr_reader :options

    option def registration_allowed_url
      @options.fetch(:registration_allowed_url)
    end

    option def authn_default_expires_in
      @options.fetch(:authn_default_expires_in, 300).to_i
    end

    option def app_id
      @options[:app_id]
    end

    option def rp_id
      @options[:rp_id]
    end

    option def store
      @store ||= Clarion::Stores.find(@options.fetch(:store).fetch(:kind)).new(store_options)
    end

    def store_options
      @store_options ||= @options.fetch(:store).dup.tap { |_| _.delete(:kind) }
    end

    option def counter
      if @options[:counter]
        @counter ||= Clarion::Counters.find(@options.fetch(:counter).fetch(:kind)).new(counter_options)
      end
    end

    def counter_options
      @counter_options ||= @options.fetch(:counter).dup.tap { |_| _.delete(:kind) }
    end

  end
end
