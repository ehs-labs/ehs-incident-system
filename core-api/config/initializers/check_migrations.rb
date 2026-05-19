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

    # The tripwire's purpose is to keep the web/sidekiq/karafka processes
    # from starting against an inconsistent schema — it must not block the
    # db:* tasks that exist precisely to bring the schema up to date. The
    # Kubernetes db-migrate Job runs `bin/rails db:create db:migrate`, which
    # loads Rails initializers before the tasks run; without this opt-out
    # the check would abort boot and the migrations would never execute.
    # Set SKIP_MIGRATION_CHECK=true on the migration Job (mirrors the env
    # var the notifier's Sequel boot already honors).
    next if ENV["SKIP_MIGRATION_CHECK"] == "true"

    begin
      ActiveRecord::Migration.check_all_pending!
    rescue ActiveRecord::PendingMigrationError => e
      Rails.logger.fatal "ABORTING BOOT — pending migrations detected"
      Rails.logger.fatal e.message
      abort "Pending migrations detected. Run `rails db:migrate` first."
    end
  end
end
