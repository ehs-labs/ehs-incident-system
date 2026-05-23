class CorrectiveActionEventPolicy < ApplicationPolicy
  def index? = CorrectiveActionPolicy.new(user, record).show?
end
