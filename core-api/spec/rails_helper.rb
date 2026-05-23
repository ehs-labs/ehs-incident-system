require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("Rails is in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "paper_trail/frameworks/rspec"

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

# PaperTrail's frameworks/rspec helper turns versioning OFF by default in tests
# and exposes `with_versioning { ... }`. The audit-history specs need versions
# captured, so we flip the default back on globally.
PaperTrail.enabled = true

# Auto-create the test DB on first run from the host. Migrations normally run
# inside the core-api container during bootstrap; the host never has the test
# DB until someone runs rspec from here. After creation, maintain_test_schema!
# loads the committed schema.rb (zero migrations needed).
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::NoDatabaseError
  ActiveRecord::Tasks::DatabaseTasks.create_current(Rails.env)
  ActiveRecord::Migration.maintain_test_schema!
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures").to_s ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
end
