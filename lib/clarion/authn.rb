require 'time'
require 'securerandom'
require 'clarion/key'

module Clarion
  class Authn
    STATUSES = %i(open cancelled verified expired)

    class << self
      def make(**kwargs)
        kwargs.delete(:id)
        kwargs.delete(:created_at)
        kwargs.delete(:status)
        kwargs.delete(:verified_at)
        kwargs.delete(:verified_key)
        new(
          id: random_id,
          created_at: Time.now,
          status: :open,
          **kwargs,
        )
      end

      def random_id
        SecureRandom.urlsafe_base64(64)
      end
    end

    def initialize(id:, name: nil, comment: nil, keys: [], created_at:, expires_at:, status:, verified_at: nil, verified_key: nil)
      @id = id
      @name = name
      @comment = comment
      @keys = keys.map{ |_| _.is_a?(Hash) ? Key.new(**_) : _}
      @created_at = created_at
      @expires_at = expires_at
      @status = status.to_sym
      @verified_at = verified_at
      @verified_key = verified_key.is_a?(Hash) ? Key.new(**verified_key) : verified_key

      @created_at = Time.xmlschema(@created_at) if @created_at && @created_at.is_a?(String)
      @expires_at = Time.xmlschema(@expires_at) if @expires_at && @expires_at.is_a?(String)
      @verified_at = Time.xmlschema(@verified_at) if @verified_at && @verified_at.is_a?(String)

      @status = :expired if expired?

      raise ArgumentError, ":status not valid" unless STATUSES.include?(@status)
    end

    attr_reader :id, :name, :comment
    attr_reader :keys
    attr_reader :created_at
    attr_reader :expires_at
    attr_reader :status
    attr_reader :verified_at, :verified_key

    def expired?
      Time.now > expires_at
    end

    def open?
      status == :open
    end

    def verified?
      status == :verified
    end

    def cancelled?
      status == :cancelled
    end

    def closed?
      !open? || expired? 
    end

    def key_for_handle(handle)
      keys.find { |_| _.handle == handle }
    end

    def verify_by_handle(handle, verified_at: Time.now)
      key = key_for_handle(handle)
      unless key
        return nil
      end
      verify(key)
      return key
    end

    def verify(key, verified_at: Time.now)
      @verified_at = verified_at
      @verified_key = key
      @status = :verified
      true
    end

    def cancel!
      @status = :cancelled
      true
    end

    def to_h(all=false)
      {
        id: id,
        status: status,
        name: name,
        comment: comment,
        created_at: created_at,
        expires_at: expires_at,
      }.tap do |h|
        if verified_key
          h[:verified_at] = verified_at
          h[:verified_key] = verified_key.to_h(all)
        end
        if all
          h[:keys] = keys.map{ |_| _.to_h(all) }
        end
      end
    end

    def as_json(*args)
      to_h(*args).tap { |_|
        _[:created_at] = _[:created_at].xmlschema if _[:created_at]
        _[:verified_at] = _[:verified_at].xmlschema if _[:verified_at]
        _[:expires_at] = _[:expires_at].xmlschema if _[:expires_at]
      }
    end

    def to_json(*args)
      as_json(*args).to_json
    end
  end
end
