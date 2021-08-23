require 'aws-sdk-s3'
require 'clarion/stores/base'
module Clarion
  module Stores
    class S3 < Base
      def initialize(region:, bucket:, prefix: nil, retry_interval: 0.1, retry_max: 10)
        @region = region
        @bucket = bucket
        @prefix = prefix

        @retry_interval = retry_interval
        @retry_max = retry_max
      end

      def store_authn(authn)
        s3.put_object(
          bucket: @bucket,
          key: authn_s3_key(authn.id),
          body: "#{authn.to_json(:all)}\n",
          content_type: 'application/json',
        )
        self
      end

      def find_authn(id)
        retry_count = 0
        json = begin
          s3.get_object(
            bucket: @bucket,
            key: authn_s3_key(id),
          ).body.read
        rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::AccessDenied
          if retry_count < @retry_max
            sleep @retry_interval
            retry_count += 1
            retry
          else
            return nil
          end
        end

        Authn.new(**JSON.parse(json, symbolize_names: true))
      end

      def authn_s3_key(authn_id)
        "#{@prefix}authn/#{authn_id}"
      end

      def s3
        @s3 ||= Aws::S3::Client.new(region: @region)
      end
    end
  end
end
