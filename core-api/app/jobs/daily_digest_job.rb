# Daily 07:00 per-user digest of open assignments. Stub — full implementation
# comes once CorrectiveAction and the dashboard scopes are in.
class DailyDigestJob
  include Sidekiq::Job

  def perform
    # TODO: emit a DailyDigestRequested event per active user with open work.
  end
end
