require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development").to_sym)

require "sequel"
require "ehs/envelope"

# -----------------------------------------------------------------------------
# Secrets — dual-source pattern (env var OR file-mounted)
# -----------------------------------------------------------------------------
def secret(name)
  ENV[name] || (path = ENV["#{name}_FILE"]) && File.read(path).strip
end

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
DB = Sequel.connect(
  ENV.fetch("DATABASE_URL"),
  max_connections: Integer(ENV.fetch("DB_POOL", "10"))
)
DB.extension :pg_array, :pg_json

# -----------------------------------------------------------------------------
# Pending-migration tripwire — refuse to boot if schema is stale.
# (Equivalent of Flyway validateOnMigrate / Liquibase validateChangeSet.)
# -----------------------------------------------------------------------------
unless ENV["SKIP_MIGRATION_CHECK"] == "true"
  Sequel.extension :migration
  migrations_dir = File.expand_path("../db/migrations", __dir__)
  if Dir.exist?(migrations_dir) && !Sequel::Migrator.is_current?(DB, migrations_dir)
    abort "Pending migrations detected. Run `bundle exec rake db:migrate` first."
  end
end

# -----------------------------------------------------------------------------
# Field-level cipher
# -----------------------------------------------------------------------------
FIELD_CIPHER = Ehs::Envelope.new(
  keys:           { "v1" => secret("FIELD_CIPHER_KEY") },
  active_version: "v1"
).freeze

# -----------------------------------------------------------------------------
# Eager load
# -----------------------------------------------------------------------------
Dir[File.expand_path("../app/models/**/*.rb",   __dir__)].sort.each { |f| require f }
Dir[File.expand_path("../app/handlers/**/*.rb", __dir__)].sort.each { |f| require f }
Dir[File.expand_path("../app/channels/**/*.rb", __dir__)].sort.each { |f| require f }
