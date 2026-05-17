ENV["RACK_ENV"]              ||= "test"
ENV["SKIP_MIGRATION_CHECK"]  ||= "true"
ENV["FIELD_CIPHER_KEY"]      ||= "aGVsbG93b3JsZGhlbGxvd29ybGRoZWxsb3dvcmxk"
ENV["DATABASE_URL"]          ||= "postgres://ehs:testpassword@localhost:5432/ehs_notifier_test"

require_relative "../config/boot"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
