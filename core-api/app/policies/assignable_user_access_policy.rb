class AssignableUserAccessPolicy < ApplicationPolicy
  def access? = user&.admin? || user&.investigator?
end
