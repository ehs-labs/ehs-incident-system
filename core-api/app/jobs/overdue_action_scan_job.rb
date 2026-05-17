# Daily scan that emits CorrectiveActionOverdue events for any action whose
# due_date passed without entering :done. Uses overdue_notified_at on
# corrective_actions to de-duplicate within a 24h window.
class OverdueActionScanJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  RENOTIFY_AFTER = 24.hours

  def perform
    cutoff = Time.current - RENOTIFY_AFTER

    CorrectiveAction
      .where(state: %w[open in_progress])
      .where("due_date < ?", Time.current)
      .where("overdue_notified_at IS NULL OR overdue_notified_at < ?", cutoff)
      .find_each do |action|
        ApplicationRecord.transaction do
          action.update_column(:overdue_notified_at, Time.current)
          action.publish_overdue_event!
        end
      end
  end
end
