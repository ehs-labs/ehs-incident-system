class CorrectiveActionPolicy < ApplicationPolicy
  def index?  = user.present?
  def show?   = scope_visible?
  def create? = same_org? && (admin? || (investigator? && site_member?))
  def update? = same_org? && (admin? || (investigator? && site_member?) || assignee?)
  def destroy? = admin? && same_org?

  # ---- State transition guards --------------------------------------------
  def start?
    same_org? && assignee? && record.may_start?
  end

  def complete?
    same_org? && assignee? && record.may_complete?
  end

  def verify?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_verify?
  end

  def cancel?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_cancel?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.joins(:incident).where(incidents: { organization_id: user.organization_id })
      case user.role.to_sym
      when :admin
        base
      when :investigator
        site_ids = user.site_memberships.pluck(:site_id)
        base.where(incidents: { site_id: site_ids })
      else # worker
        base.where(
          "corrective_actions.assignee_id = :uid OR incidents.reporter_id = :uid",
          uid: user.id
        )
      end
    end
  end

  private

  def same_org?     = record.incident.organization_id == user.organization_id
  def admin?        = user.admin?
  def investigator? = user.investigator?
  def worker?       = user.worker?
  def assignee?     = record.assignee_id == user.id
  def site_member?  = user.site_memberships.exists?(site_id: record.incident.site_id)

  def scope_visible?
    self.class::Scope.new(user, CorrectiveAction.where(id: record.id)).resolve.exists?
  end
end
