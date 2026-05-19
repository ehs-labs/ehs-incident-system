ENV["RACK_ENV"]              = "test"
ENV["SKIP_MIGRATION_CHECK"]  ||= "true"
# 32 zero-bytes encoded as base64 — matches .env.example convention
ENV["FIELD_CIPHER_KEY"]      ||= "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# Force-set the test database — `||=` would let an inherited production URL slip
# through when specs run inside a long-running container, and the per-example
# truncates below would wipe real data.
ENV["DATABASE_URL"]          = "postgres://ehs:devpassword@postgres:5432/ehs_notifier_test"
ENV["KAFKA_BROKERS"]         ||= "kafka:9092"
ENV["KARAPACE_URL"]          ||= "http://karapace:8081"

require_relative "../config/boot"
require "karafka/testing/rspec/helpers"

# Boot the Karafka routing table so karafka-testing can resolve consumers.
# The app does not connect to the broker during setup — it only reads ENV.
require_relative "../karafka"
Karafka::App.initialize!

RSpec.configure do |config|
  config.include Karafka::Testing::RSpec::Helpers

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

  # Intercept email delivery; do not actually connect to MailCatcher in specs.
  config.before(:suite) do
    Mail.defaults do
      delivery_method :test
    end
  end

  config.before do
    Mail::TestMailer.deliveries.clear
    DB[:delivery_log].truncate
    DB[:users_mirror].truncate
  end
end
