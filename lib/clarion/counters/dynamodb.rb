require 'aws-sdk-dynamodb'
require 'clarion/counters/base'

module Clarion
  module Counters
    class Dynamodb < Base
      def initialize(table_name:, region:)
        @table_name = table_name
        @region = region
      end

      def get(key)
        item = table.query(
          limit: 1,
          select: 'ALL_ATTRIBUTES',
          key_condition_expression: 'handle = :handle',
          expression_attribute_values: {":handle" => key.handle},
        ).items.first

        item && item['key_counter']
      end

      def store(key)
        table.update_item(
          key: {
            'handle' => key.handle,
          },
          update_expression: 'SET key_counter = :new',
          condition_expression: 'attribute_not_exists(key_counter) OR key_counter < :new',
          expression_attribute_values: {':new' => key.counter},
        )
      rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
      end

      def table
        @table ||= dynamodb.table(@table_name)
      end

      def dynamodb
        @dynamodb ||= Aws::DynamoDB::Resource.new(region: @region)
      end

    end
  end
end
