# Clarion: WebAuthn helper for CLI operations (e.g. SSH Log in)

![](https://img.sorah.jp/s/ssh-u2f.gif)

Clarion is a web-based frontend to allow remote,non-browser operations (CLI) to perform 2FA on their users.

## How it works

Any software/scripts want to perform 2FA _(app)_ creates _a request_ on Clarion. Then _app_ requests user to visit a request specific path on Clarion.
Clarion then performs 2FA on behalf of _app,_ and finally returns an authentication result to _app._

Clarion also provides a way to retrieve user's key handle and public key.

Note that Clarion itself doesn't manage users' key handle and public key. User information should be provided every time when requesting authentication.

## Set up

Clarion is a Rack application. Docker image is also available.

See [config.ru](./config.ru) for detailed configuration. The following environment variable is supported by the bundled config.ru.

- `SECRET_KEY_BASE` (required)
- `CLARION_REGISTRATION_ALLOWED_URL` (required): Regexp that matches against URLs. Only matched URLs are allowed for key registration callback.
- `CLARION_AUTHN_DEFAULT_EXPIRES_IN` (default: `300`): authn lifetime in seconds.
- `CLARION_STORE` (required, default: `s3`): See [docs/stores.md](./docs/stores.md)
- S3 store:
  - `CLARION_STORE_S3_BUCKET`
  - `CLARION_STORE_S3_REGION`
  - `CLARION_STORE_S3_PREFIX` (optional, recommended to end with `/`)
- `CLARION_COUNTER` (optional, default: `dynamodb`): See [docs/counters.md](./docs/counters.md)
  - `CLARION_COUNTER_DYNAMODB_TABLE`
  - `CLARION_COUNTER_DYNAMODB_REGION`


## Usage

### Real world example: SSH log in

See [./examples/pam-u2f](./examples/pam-u2f)

### Test implementation

Visit `/test` exists in your application. This endpoint doesn't work for multi-process/multi-threaded deployment.

See [app/views/test.erb](./app/views/test.erb), [app/views/test_callback.erb](./app/views/test_callback.erb), [app/public/test.js](./app/public/test.js) for implementation.

### API

See [docs/api.md](./docs/api.md)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## To-dos

- [ ] Write an integration test
- [ ] Write a unit test

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/clarion.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
