require "aasm"

class Incident < ApplicationRecord
  include AASM
  include TenantScoped
  include PgSearch::Model

  has_paper_trail

  # ----- Associations --------------------------------------------------------
  belongs_to :organization
  belongs_to :site
  belongs_to :reporter, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true

  has_many_attached :photos

  has_many :witnesses, dependent: :destroy
  has_many :comments,  dependent: :destroy

  # ----- Validations ---------------------------------------------------------
  SEVERITIES = (1..5).freeze
  VALID_TYPES = %w[collision slip fall near_miss exposure mechanical electrical fire other].freeze

  validates :incident_type, presence: true, inclusion: { in: VALID_TYPES }
  validates :severity,      presence: true, inclusion: { in: SEVERITIES.to_a }
  validates :summary,       presence: true, length: { maximum: 200 }
  # occurred_at + location are collected at step 2 of the multi-step form, so
  # a draft saved at step 1 may not have them yet. The AASM `submit` guard
  # (`ready_for_submission?`) re-checks every required field at transition
  # time so a user can never reach `submitted` with an incomplete payload.
  validates :occurred_at, presence: true, unless: :draft?
  validates :location,    presence: true, length: { maximum: 200 }, unless: :draft?
  validate  :reporter_in_same_org
  validate  :site_in_same_org

  # ----- Full-text search ----------------------------------------------------
  pg_search_scope :search,
    against: { summary: "A", description: "B", location: "C", root_cause: "B" },
    using: { tsearch: { prefix: true, dictionary: "english", tsvector_column: "tsv" } }

  before_save :rebuild_tsv

  # ----- Scopes --------------------------------------------------------------
  scope :open,           -> { where.not(state: "closed") }
  scope :by_severity,    ->(s) { where(severity: s) }
  scope :overdue_triage, -> { where(state: "submitted").where("submitted_at < ?", 24.hours.ago) }

  # ----- State machine ------------------------------------------------------
  # See docs/design/state-machines.md for the full diagram.
  aasm column: :state, whiny_transitions: false do
    state :draft, initial: true
    state :submitted
    state :investigating
    state :pending_closure
    state :closed

    event :submit do
      transitions from: :draft, to: :submitted, guard: :ready_for_submission?
      after do
        update_column(:submitted_at, Time.current)
        publish_event!("IncidentSubmitted", recipient_user_ids: triage_recipients)
      end
    end

    event :triage do
      transitions from: %i[submitted closed], to: :investigating, guard: :assignee_present?
      after do
        update_column(:triaged_at, Time.current)
        publish_event!("IncidentAssigned", recipient_user_ids: [assignee_id].compact)
      end
    end

    event :reject do
      transitions from: :investigating, to: :submitted
    end

    event :actions_assigned do
      transitions from: :investigating, to: :pending_closure
    end

    event :verify do
      transitions from: :pending_closure, to: :closed
      after do
        update_column(:closed_at, Time.current)
        publish_event!("IncidentClosed", recipient_user_ids: [reporter_id, assignee_id].compact.uniq)
      end
    end

    event :reopen do
      transitions from: :closed, to: :investigating
    end

    event :edit do
      transitions from: :draft, to: :draft
    end
  end

  # ----- Public helpers ------------------------------------------------------

  # SLA window (in seconds) for triage by severity. Per the design doc:
  #   S1, S2 -> 4h ;  S3 -> 24h ;  S4, S5 -> 72h
  # Per-organization overrides via OrganizationSetting#sla_overrides take precedence.
  def triage_sla
    override = organization&.setting&.sla_overrides&.dig(severity.to_s, "triage_seconds")
    return override.to_i.seconds if override.is_a?(Integer) && override.positive?

    case severity
    when 1, 2 then 4.hours
    when 3    then 24.hours
    else            72.hours
    end
  end

  def triage_deadline
    return nil unless submitted_at
    submitted_at + triage_sla
  end

  def triage_overdue?
    state == "submitted" && triage_deadline && Time.current > triage_deadline
  end

  private

  def rebuild_tsv
    return unless summary_changed? || description_changed? || location_changed? || root_cause_changed?

    self.tsv = nil # let pg_search compute it via the column; rebuild via SQL when needed
  end

  def ready_for_submission?
    [incident_type, severity, occurred_at, location, summary, description].all?(&:present?)
  end

  def assignee_present?
    assignee_id.present?
  end

  def reporter_in_same_org
    return if reporter.blank? || reporter.organization_id == organization_id
    errors.add(:reporter, "must belong to the same organization")
  end

  def site_in_same_org
    return if site.blank? || site.organization_id == organization_id
    errors.add(:site, "must belong to the same organization")
  end

  # Users who should be notified about a fresh submission: investigators &
  # admins on the same site, plus the reporter.
  def triage_recipients
    return [] unless site

    User.where(organization_id: organization_id)
        .where(role: [User.roles[:investigator], User.roles[:admin]])
        .joins(:site_memberships)
        .where(site_memberships: { site_id: site_id })
        .where(deleted_at: nil)
        .distinct
        .pluck(:id) | [reporter_id].compact
  end

  def publish_event!(event_type, recipient_user_ids:)
    EventBus.publish!(
      event_type:        event_type,
      topic:             "incidents.v1",
      partition_key:     organization_id.to_s,
      org_id:            organization_id,
      actor_id:          (Current.user&.id || reporter_id),
      subject:           event_subject_for(event_type),
      recipient_user_ids: recipient_user_ids
    )
  end

  # Each event type has its own subject schema in schemas/events/v1/.
  # Returns only the fields the schema declares — and matches the schema's
  # primitive types: IDs are stringified (schema: string), severity stays
  # Integer (schema: int), timestamps go through EventBus#coerce.
  def event_subject_for(event_type)
    case event_type
    when "IncidentSubmitted"
      { incident_id: id.to_s, site_id: site_id.to_s, reporter_id: reporter_id.to_s,
        severity: severity, summary: summary }
    when "IncidentAssigned"
      { incident_id: id.to_s, assignee_id: assignee_id.to_s, severity: severity,
        site_id: site_id.to_s }
    when "IncidentClosed"
      { incident_id: id.to_s, site_id: site_id.to_s, severity: severity,
        closed_at: (closed_at || Time.current) }
    else
      { incident_id: id.to_s }
    end
  end
end
