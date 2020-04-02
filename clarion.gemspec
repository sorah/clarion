
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "clarion/version"

Gem::Specification.new do |spec|
  spec.name          = "clarion"
  spec.version       = Clarion::VERSION
  spec.authors       = ["Sorah Fukumori"]
  spec.email         = ["sorah@cookpad.com"]

  spec.summary       = %q{Web-based WebAuthn (U2F) Helper for CLI operations (SSH login...)}
  spec.homepage      = "https://github.com/sorah/clarion"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "webauthn", '< 2'
  spec.add_dependency "sinatra"
  spec.add_dependency "erubis"
  spec.add_dependency "aws-sdk-s3"
  spec.add_dependency "aws-sdk-dynamodb"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
end
