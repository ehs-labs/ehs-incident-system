# Hourly scan for incidents past their severity-based triage SLA. Emits
# SlaBreached events; the notifier fans out to admins and the assigned
# investigator.
class SlaBreachScanJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform
    Incident.where(state: "submitted", sla_breached_at: nil).find_each do |incident|
      next unless incident.triage_overdue?

      incident.update_column(:sla_breached_at, Time.current)

      EventBus.publish!(
        event_type:    "SlaBreached",
        topic:         "system.v1",
        partition_key: incident.organization_id.to_s,
        org_id:        incident.organization_id,
        actor_id:      "system",
        subject: {
          incident_id:          incident.id,
          site_id:              incident.site_id,
          severity:             incident.severity,
          sla_kind:             "TRIAGE",
          breached_threshold_at: incident.triage_deadline.iso8601(3)
        },
        recipient_user_ids: admin_recipients(incident)
      )
    end
  end

  private

  def admin_recipients(incident)
    User.where(organization_id: incident.organization_id, role: User.roles[:admin])
        .where(deleted_at: nil)
        .pluck(:id) + [ incident.assignee_id ].compact
  end
end
