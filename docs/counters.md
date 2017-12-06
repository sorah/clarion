# Counters

Clarion _counter_ is responsible to store U2F device counters. It's optional but highly recommended to set up.

## `memory`: Memory

Memory store for development purpose.

## `dynamodb`: AWS DynamoDB

- `table_name`
- `region`

Table should have partition key `handle` (String).
