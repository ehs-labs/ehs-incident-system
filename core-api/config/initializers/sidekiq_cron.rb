# Loads cron schedules into Sidekiq on boot. sidekiq-cron stopped reading the
# :schedule: key in sidekiq.yml automatically in 2.x — schedules are now loaded
# from a dedicated YAML file (or a Hash) by the host application.
#
# We read the same config/sidekiq.yml file so the operator has a single source
# of truth, then push the :schedule: section into Sidekiq::Cron::Job.

Rails.application.config.after_initialize do
  next unless Sidekiq.server?
  next unless defined?(Sidekiq::Cron::Job)

  schedule_file = Rails.root.join("config/sidekiq.yml")
  next unless File.exist?(schedule_file)

  schedule = YAML.load_file(schedule_file).dig(:schedule) || YAML.load_file(schedule_file).dig("schedule") || {}
  next if schedule.empty?

  Sidekiq::Cron::Job.load_from_hash!(schedule)
  Rails.logger.info "[sidekiq-cron] Loaded #{schedule.size} scheduled jobs"
end
