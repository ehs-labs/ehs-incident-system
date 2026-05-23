# Sensible defaults so `cd core-api && bundle exec rspec` works without
# manually exporting the docker-compose env. Anything already set in the
# shell (or by dotenv-rails) wins via `||=`.
#
# These are TEST-ONLY values — never used outside RAILS_ENV=test.
ENV["RAILS_ENV"]           ||= "test"
ENV["JWT_SECRET"]          ||= "test-jwt-secret-do-not-use-outside-tests"
ENV["JWT_DENYLIST_SECRET"] ||= "test-jwt-denylist-secret-do-not-use-outside-tests"
# 32 zero-bytes, base64-encoded — matches the .env.example convention and the
# notifier's spec_helper default.
ENV["FIELD_CIPHER_KEY"]    ||= "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# Postgres in this repo runs in docker; on the host it's only reachable via
# the IPv4 loopback. Override the "postgres" hostname default from
# config/database.yml when running specs from the host.
ENV["POSTGRES_HOST"]       ||= "127.0.0.1"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
