require "aasm"

class CorrectiveAction < ApplicationRecord
  include AASM

  has_paper_trail

  # ----- Associations --------------------------------------------------------
  belongs_to :incident
  belongs_to :assignee,   class_name: "User"
  belongs_to :created_by, class_name: "User"

  has_many_attached :evidence

  delegate :organization_id, to: :incident

  # ----- Validations ---------------------------------------------------------
  validates :title,    presence: true, length: { maximum: 200 }
  validates :due_date, presence: true
  validate  :due_date_in_future_on_create
  validate  :assignee_in_same_org

  # ----- Scopes --------------------------------------------------------------
  scope :open_states, -> { where(state: %w[open in_progress]) }
  scope :overdue,     -> { open_states.where("due_date < ?", Time.current) }

  # ----- State machine -------------------------------------------------------
  # See docs/design/state-machines.md for the full diagram.
  aasm column: :state, whiny_transitions: false do
    state :open, initial: true
    state :in_progress
    state :done
    state :verified
    state :cancelled

    event :start do
      transitions from: :open, to: :in_progress
    end

    event :complete do
      transitions from: :in_progress, to: :done
      after { update_column(:completed_at, Time.current) }
    end

    event :verify do
      transitions from: :done, to: :verified
      after do
        update_column(:verified_at, Time.current)
        maybe_close_parent_incident!
      end
    end

    event :cancel do
      transitions from: %i[open in_progress done], to: :cancelled
    end
  end

  # ----- Event publishing ----------------------------------------------------

  # Called by the controller after #save on create. AASM after-create hooks
  # are awkward (assignee may change in the same save), so we mirror Incident
  # and trigger from the controller explicitly.
  def publish_assigned_event!
    publish_event!("CorrectiveActionAssigned", recipient_user_ids: [ assignee_id ].compact)
  end

  def publish_overdue_event!
    publish_event!(
      "CorrectiveActionOverdue",
      recipient_user_ids: [ incident.reporter_id, assignee_id ].compact.uniq,
      actor_id_override: "system"
    )
  end

  def overdue?
    %w[open in_progress].include?(state) && due_date.present? && due_date < Time.current
  end

  private

  def publish_event!(event_type, recipient_user_ids:, actor_id_override: nil)
    EventBus.publish!(
      event_type:        event_type,
      topic:             "corrective_actions.v1",
      partition_key:     organization_id.to_s,
      org_id:            organization_id,
      actor_id:          actor_id_override || (Current.user&.id || created_by_id),
      subject:           event_subject_for(event_type),
      recipient_user_ids: recipient_user_ids
    )
  end

  # Returns only the fields the matching Avro schema declares, with IDs
  # stringified. EventBus#coerce maps Date -> int (epoch days) for the
  # logical-type date fields.
  def event_subject_for(event_type)
    case event_type
    when "CorrectiveActionAssigned"
      {
        action_id:   id.to_s,
        incident_id: incident_id.to_s,
        assignee_id: assignee_id.to_s,
        title:       title,
        due_date:    due_date.to_date
      }
    when "CorrectiveActionOverdue"
      {
        action_id:    id.to_s,
        incident_id:  incident_id.to_s,
        assignee_id:  assignee_id.to_s,
        due_date:     due_date.to_date,
        days_overdue: ((Time.current.to_date - due_date.to_date).to_i)
      }
    else
      { action_id: id.to_s }
    end
  end

  # When every sibling corrective action on the incident is verified and the
  # incident is sitting at :pending_closure, push it to :closed via the
  # existing AASM event (which emits IncidentClosed).
  def maybe_close_parent_incident!
    return unless incident.state == "pending_closure"

    siblings = CorrectiveAction.where(incident_id: incident_id).where.not(state: "cancelled")
    return unless siblings.any? && siblings.all? { |a| a.state == "verified" }

    incident.verify!
  end

  def due_date_in_future_on_create
    return unless new_record? && due_date.present?
    return if due_date > Time.current

    errors.add(:due_date, "must be in the future")
  end

  def assignee_in_same_org
    return if assignee.blank? || incident.blank?
    return if assignee.organization_id == incident.organization_id

    errors.add(:assignee, "must belong to the same organization as the incident")
  end
end
