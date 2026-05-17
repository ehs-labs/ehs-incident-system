class WitnessPolicy < ApplicationPolicy
  def index?   = visible?
  def show?    = visible?
  def create?  = same_org? && incident_updatable?
  def update?  = same_org? && admin_or_investigator?
  def destroy? = same_org? && admin_or_investigator?

  class Scope < ApplicationPolicy::Scope
    def resolve
      visible_incident_ids = IncidentPolicy::Scope.new(user, Incident).resolve.pluck(:id)
      scope.where(incident_id: visible_incident_ids).where(deleted_at: nil)
    end
  end

  private

  def incident
    record.incident
  end

  def same_org?
    incident&.organization_id == user.organization_id
  end

  def visible?
    return false unless incident
    IncidentPolicy.new(user, incident).show?
  end

  def admin_or_investigator?
    user.admin? || (user.investigator? && investigator_on_site?)
  end

  def investigator_on_site?
    user.site_memberships.exists?(site_id: incident.site_id)
  end

  def incident_updatable?
    IncidentPolicy.new(user, incident).update?
  end
end
