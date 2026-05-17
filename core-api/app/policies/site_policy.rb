class SitePolicy < ApplicationPolicy
  def index?   = user.present?
  def show?    = same_org?
  def create?  = user.admin?
  def update?  = user.admin? && same_org?
  def destroy? = user.admin? && same_org?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def same_org? = record.organization_id == user.organization_id
end
