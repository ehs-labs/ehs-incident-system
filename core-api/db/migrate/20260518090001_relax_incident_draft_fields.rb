class RelaxIncidentDraftFields < ActiveRecord::Migration[7.2]
  # The multi-step "Report an incident" form lets users save a draft at any
  # step — including before they've reached the "where & when" step. The
  # original migration required `occurred_at` and `location` on every save,
  # which made draft persistence fail.
  #
  # Submit-time enforcement still happens via the AASM guard
  # Incident#ready_for_submission? (occurred_at + location + summary +
  # description + incident_type + severity all required to transition from
  # `draft` to `submitted`), so the user can never reach `submitted` with
  # an incomplete payload — only the DB constraint for drafts is loosened.
  def change
    safety_assured do
      change_column_null :incidents, :occurred_at, true
      change_column_null :incidents, :location,    true
    end
  end
end
