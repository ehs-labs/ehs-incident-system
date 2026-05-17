class Site < ApplicationRecord
  include TenantScoped

  belongs_to :organization
  has_many :site_memberships, dependent: :destroy
  has_many :users,            through: :site_memberships
  has_many :incidents,        dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :name, uniqueness: { scope: :organization_id }
  validates :timezone, presence: true
  validate  :timezone_resolvable

  private

  def timezone_resolvable
    return if timezone.blank?
    # Accept any name TZInfo recognises (e.g. "UTC", "Australia/Sydney").
    TZInfo::Timezone.get(timezone)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:timezone, "is not a recognised IANA timezone")
  end
end
