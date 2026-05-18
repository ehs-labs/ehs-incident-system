class IncidentPolicy < ApplicationPolicy
  def index?   = user.present?
  def show?    = same_org? && (admin_or_investigator? || own_incident?)
  def create?  = same_org?
  def update?  = same_org? && (admin? || (investigator? && site_member?) || (worker? && draft? && record.reporter_id == user.id))
  def destroy? = admin? && same_org?

  # ---- State transition guards ---------------------------------------------
  def submit?
    same_org? && (admin? || record.reporter_id == user.id) && record.may_submit?
  end

  def triage?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_triage?
  end

  def verify?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_verify?
  end

  def reopen?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_reopen?
  end

  def reject?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_reject?
  end

  def actions_assigned?
    same_org? && (admin? || (investigator? && site_member?)) && record.may_actions_assigned?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(organization_id: user.organization_id)
      case user.role.to_sym
      when :admin
        base
      when :investigator
        site_ids = user.site_memberships.pluck(:site_id)
        base.where(site_id: site_ids)
      else # worker
        base.where(reporter_id: user.id)
      end
    end
  end

  private

  def same_org?         = record.organization_id == user.organization_id
  def admin?            = user.admin?
  def investigator?     = user.investigator?
  def worker?           = user.worker?
  def admin_or_investigator? = admin? || (investigator? && site_member?)
  def own_incident?     = record.reporter_id == user.id
  def draft?            = record.state == "draft"
  def site_member?      = user.site_memberships.exists?(site_id: record.site_id)
end
