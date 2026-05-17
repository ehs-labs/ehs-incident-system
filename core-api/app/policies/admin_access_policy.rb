class AdminAccessPolicy < ApplicationPolicy
  def access? = user&.admin?
end
