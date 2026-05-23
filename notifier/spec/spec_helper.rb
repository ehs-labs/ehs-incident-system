# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['SKIP_MIGRATION_CHECK']  ||= 'true'
# 32 zero-bytes encoded as base64 — matches .env.example convention
ENV['FIELD_CIPHER_KEY']      ||= 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
# Default the test database. Lets an externally-provided DATABASE_URL win so
# CI can point at its service container.
#
# The default host is 127.0.0.1 because the only place tests actually run is
# the host machine — the notifier production image excludes test gems, so it
# can't run rspec inside the container. (Docker DNS would let `postgres`
# resolve in-container, but not from the host, where this matters.)
#
# Guard against a production URL slipping through (the per-example truncates
# below would wipe real data) by requiring the database name to end in `_test`.
ENV['DATABASE_URL']          ||= 'postgres://ehs:devpassword@127.0.0.1:5432/ehs_notifier_test'
unless ENV.fetch('DATABASE_URL').include?('_test')
  abort "DATABASE_URL must point at a test database (name ending in _test). Got: #{ENV['DATABASE_URL']}"
end
ENV['KAFKA_BROKERS']         ||= 'kafka:9092'
ENV['KARAPACE_URL']          ||= 'http://karapace:8081'

# Auto-create + migrate the test DB on first run from the host. boot.rb opens
# a Sequel connection at load time and aborts if the DB is missing, so we have
# to provision it before requiring boot. Mirrors what the Rakefile does, but
# without shelling out.
require 'uri'
require 'sequel'
db_url   = ENV.fetch('DATABASE_URL')
db_name  = URI.parse(db_url).path.delete_prefix('/')
admin_url = db_url.sub(%r{/[^/]+$}, '/postgres')
begin
  Sequel.connect(db_url) { |db| db.test_connection }
rescue Sequel::DatabaseConnectionError
  Sequel.connect(admin_url) do |db|
    next if db.fetch('SELECT 1 FROM pg_database WHERE datname = ?', db_name).first
    db.run("CREATE DATABASE #{db_name}")
  end
end
Sequel.extension :migration
Sequel.connect(db_url) do |db|
  Sequel::Migrator.run(db, File.expand_path('../db/migrations', __dir__))
end

require_relative '../config/boot'
require 'karafka/testing/rspec/helpers'

# Boot the Karafka routing table so karafka-testing can resolve consumers.
# The app does not connect to the broker during setup — it only reads ENV.
require_relative '../karafka'
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
