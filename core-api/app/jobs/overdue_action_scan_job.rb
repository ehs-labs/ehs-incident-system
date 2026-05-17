# Daily scan that emits CorrectiveActionOverdue events for any action whose
# due_date passed without entering :done. Stub — CorrectiveAction is a
# follow-up milestone; this prevents Sidekiq from erroring on the missing
# class while the cron schedule is in place.
class OverdueActionScanJob
  include Sidekiq::Job

  def perform
    # TODO: implement once CorrectiveAction model lands.
  end
end
