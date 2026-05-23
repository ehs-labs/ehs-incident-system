require "aasm"

class CorrectiveAction < ApplicationRecord
  include AASM

  has_paper_trail

  # ----- Associations --------------------------------------------------------
  belongs_to :incident
  belongs_to :assignee,   class_name: "User"
  belongs_to :created_by, class_name: "User"

  has_many_attached :evidence

  has_many :events, class_name: "CorrectiveActionEvent", dependent: :destroy

  # Set by the controller (or test) before invoking an AASM event method.
  # AASM events don't accept arguments, so we pass the operator's note through
  # this thread-local-per-instance attribute. Cleared inside log_transition!.
  attr_accessor :pending_note

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
      after do
        log = log_transition!(:started)
        publish_event!(
          "CorrectiveActionStarted",
          recipient_user_ids: [ created_by_id, incident.assignee_id ].compact.uniq,
          note: log.note
        )
      end
    end

    event :complete do
      transitions from: :in_progress, to: :done
      after do
        update_column(:completed_at, Time.current)
        log = log_transition!(:completed)
        publish_event!(
          "CorrectiveActionCompleted",
          recipient_user_ids: completion_recipient_ids,
          note: log.note
        )
      end
    end

    event :verify do
      transitions from: :done, to: :verified
      after do
        update_column(:verified_at, Time.current)
        log = log_transition!(:verified)
        publish_event!(
          "CorrectiveActionVerified",
          recipient_user_ids: [ assignee_id ].compact,
          note: log.note
        )
        maybe_close_parent_incident!
      end
    end

    event :cancel do
      transitions from: %i[open in_progress done], to: :cancelled
      after do
        log = log_transition!(:cancelled)
        publish_event!(
          "CorrectiveActionCancelled",
          recipient_user_ids: [ assignee_id ].compact,
          note: log.note
        )
      end
    end
  end

  # ----- Event publishing ----------------------------------------------------

  # Called by the controller after #save on create. AASM after-create hooks
  # are awkward (assignee may change in the same save), so we mirror Incident
  # and trigger from the controller explicitly.
  def publish_assigned_event!
    publish_event!(
      "CorrectiveActionAssigned",
      recipient_user_ids: [ assignee_id ].compact,
      note: events.where(event_name: "assigned").order(:created_at).last&.note
    )
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

  def publish_event!(event_type, recipient_user_ids:, note: nil, actor_id_override: nil)
    EventBus.publish!(
      event_type:        event_type,
      topic:             "corrective_actions.v1",
      partition_key:     organization_id.to_s,
      org_id:            organization_id,
      actor_id:          actor_id_override || (Current.user&.id || created_by_id),
      subject:           event_subject_for(event_type, note: note),
      recipient_user_ids: recipient_user_ids
    )
  end

  # Returns only the fields the matching Avro schema declares, with IDs
  # stringified. EventBus#coerce maps Date -> int (epoch days) for the
  # logical-type date fields. Every event subject carries an optional `note`.
  def event_subject_for(event_type, note: nil)
    base =
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
      when "CorrectiveActionCompleted"
        {
          action_id:    id.to_s,
          incident_id:  incident_id.to_s,
          assignee_id:  assignee_id.to_s,
          title:        title,
          completed_at: completed_at || Time.current
        }
      when "CorrectiveActionStarted", "CorrectiveActionVerified", "CorrectiveActionCancelled"
        {
          action_id:   id.to_s,
          incident_id: incident_id.to_s,
          assignee_id: assignee_id.to_s,
          title:       title
        }
      else
        { action_id: id.to_s }
      end

    base.merge(note: note)
  end

  def log_transition!(event_name)
    events.create!(
      event_name: event_name.to_s,
      actor_id:   Current.user.id,
      note:       pending_note
    ).tap { self.pending_note = nil }
  end

  # Investigators who should learn the action is ready to verify: the user who
  # created the action plus the investigator owning the parent incident.
  def completion_recipient_ids
    [ created_by_id, incident.assignee_id ].compact.uniq
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
