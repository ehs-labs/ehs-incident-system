class Witness < ApplicationRecord
  include TenantScoped

  # ----- Associations --------------------------------------------------------
  belongs_to :incident

  has_one :site,         through: :incident
  has_one :organization, through: :incident

  # ----- Validations ---------------------------------------------------------
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  validates :name,      presence: true, length: { maximum: 120 }
  validates :email,     format: { with: EMAIL_FORMAT }, allow_blank: true
  validates :phone,     length: { maximum: 40 }, allow_blank: true
  validates :statement, length: { maximum: 10_000 }, allow_blank: true

  # ----- Scopes --------------------------------------------------------------
  scope :active,  -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Override TenantScoped#for_org — witnesses inherit org via incident.
  def self.for_org(org_or_id)
    org_id = org_or_id.is_a?(Organization) ? org_or_id.id : org_or_id
    joins(:incident).where(incidents: { organization_id: org_id })
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end
end
