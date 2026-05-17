class OrganizationSetting < ApplicationRecord
  belongs_to :organization

  # Stored as { "1" => { "triage_seconds" => 14400 }, ... , "actions_due_seconds" => 604800 }
  # Severity keys are stringified to match jsonb round-trip.
  validates :organization_id, uniqueness: true
  validate  :sla_overrides_shape

  SEVERITY_KEYS = %w[1 2 3 4 5].freeze

  private

  def sla_overrides_shape
    return if sla_overrides.blank?
    unless sla_overrides.is_a?(Hash)
      errors.add(:sla_overrides, "must be an object")
      return
    end

    sla_overrides.each do |key, value|
      next if key == "actions_due_seconds"

      unless SEVERITY_KEYS.include?(key.to_s)
        errors.add(:sla_overrides, "has unknown key #{key.inspect}")
        next
      end
      next if value.is_a?(Hash) && (value["triage_seconds"].nil? || value["triage_seconds"].is_a?(Integer))

      errors.add(:sla_overrides, "value for #{key} must be a hash with optional integer triage_seconds")
    end
  end
end
