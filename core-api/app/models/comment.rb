class Comment < ApplicationRecord
  include TenantScoped

  # ----- Associations --------------------------------------------------------
  belongs_to :incident
  belongs_to :author, class_name: "User"

  has_one :organization, through: :incident

  # ----- Validations ---------------------------------------------------------
  validates :body, presence: true, length: { maximum: 10_000 }
  validate  :author_in_same_org

  # Override TenantScoped#for_org — comments inherit org via incident.
  def self.for_org(org_or_id)
    org_id = org_or_id.is_a?(Organization) ? org_or_id.id : org_or_id
    joins(:incident).where(incidents: { organization_id: org_id })
  end

  private

  def author_in_same_org
    return if author.blank? || incident.blank?
    return if author.organization_id == incident.organization_id

    errors.add(:author, "must belong to the same organization as the incident")
  end
end
