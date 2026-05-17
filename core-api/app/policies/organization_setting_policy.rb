class OrganizationSettingPolicy < ApplicationPolicy
  def show?   = user&.admin? && same_org?
  def update? = user&.admin? && same_org?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.admin?
      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def same_org? = record.organization_id == user.organization_id
end
