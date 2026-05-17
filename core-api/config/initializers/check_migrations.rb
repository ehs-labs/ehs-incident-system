# ============================================================================
# Boot-time tripwire — refuses to start if any migration is pending.
#
# Equivalent to Flyway's `validateOnMigrate` / Liquibase's `validateChangeSet`.
# Always active in production; opt-in in other envs via STRICT_MIGRATION_CHECK.
# ============================================================================

Rails.application.config.after_initialize do
  if Rails.env.production? || ENV["STRICT_MIGRATION_CHECK"] == "true"
    next if defined?(Rails::Console)            # don't block `rails console`
    next if Rails.const_defined?(:Generators)   # don't block generators

    begin
      ActiveRecord::Migration.check_all_pending!
    rescue ActiveRecord::PendingMigrationError => e
      Rails.logger.fatal "ABORTING BOOT — pending migrations detected"
      Rails.logger.fatal e.message
      abort "Pending migrations detected. Run `rails db:migrate` first."
    end
  end
end
