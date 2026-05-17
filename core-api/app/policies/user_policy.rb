class UserPolicy < ApplicationPolicy
  def index?   = same_org?
  def show?    = same_org?
  def invite?  = user.admin? && same_org?
  def lock?    = user.admin? && same_org?
  def unlock?  = user.admin? && same_org?
  def destroy? = user.admin? && same_org?
  def update?  = user.admin? && same_org?
  def create?  = user.admin?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: user.organization_id)
    end
  end

  private

  def same_org? = record.organization_id == user.organization_id
end
