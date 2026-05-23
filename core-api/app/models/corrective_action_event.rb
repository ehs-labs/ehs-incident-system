class CorrectiveActionEvent < ApplicationRecord
  EVENT_NAMES = %w[assigned started completed verified cancelled].freeze

  belongs_to :corrective_action
  belongs_to :actor, class_name: "User"

  validates :event_name, inclusion: { in: EVENT_NAMES }
  validates :note, length: { maximum: 2000 }, allow_nil: true
end
