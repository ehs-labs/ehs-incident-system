require_relative "lib/ehs/envelope/version"

Gem::Specification.new do |spec|
  spec.name          = "ehs-envelope"
  spec.version       = Ehs::Envelope::VERSION
  spec.authors       = ["Denis Khaziev"]
  spec.email         = ["denis.khaziev@gmail.com"]

  spec.summary       = "AES-256-GCM field-level encryption for PII in shared event payloads"
  spec.description   = <<~DESC
    A tiny shared library used by both the EHS core-api (Rails) and notifier
    (Sinatra) services to encrypt sensitive fields (email, name, telegram chat id)
    before publishing on the users.v1 Kafka topic, and decrypt them on consume.

    Supports key versioning via the wire-format prefix (e.g. "v1:nonce:ct:tag")
    so keys can be rotated through a dual-decrypt window.
  DESC
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.glob("lib/**/*") + ["ehs-envelope.gemspec", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.65"
end
