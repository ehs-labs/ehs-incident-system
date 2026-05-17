class SiteMembership < ApplicationRecord
  belongs_to :user
  belongs_to :site

  validates :user_id, uniqueness: { scope: :site_id }
  validate  :same_organization

  private

  def same_organization
    return if user.blank? || site.blank?
    return if user.organization_id == site.organization_id

    errors.add(:base, "user and site must belong to the same organization")
  end
end
