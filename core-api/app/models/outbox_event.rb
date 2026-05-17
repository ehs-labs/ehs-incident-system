# Transactional-outbox record. Written in the same DB transaction as the
# state change that caused it; OutboxShipperJob ships them to Kafka and marks
# published_at. Idempotent on event_id.
class OutboxEvent < ApplicationRecord
  validates :event_id,      presence: true, uniqueness: true
  validates :event_type,    presence: true
  validates :topic,         presence: true
  validates :partition_key, presence: true
  validates :payload,       presence: true

  scope :pending, -> { where(published_at: nil).order(:id) }

  def published?
    published_at.present?
  end

  def mark_published!
    update!(published_at: Time.current, last_error: nil)
  end

  def mark_failed!(error)
    update!(attempt_count: attempt_count + 1, last_error: error.to_s.truncate(1000))
  end
end
