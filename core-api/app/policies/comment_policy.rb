class CommentPolicy < ApplicationPolicy
  def index?   = visible?
  def show?    = visible?
  def create?  = same_org? && incident_updatable?

  # Comment authors may edit/delete their own; admins and on-site investigators
  # may always edit/delete.
  def update?  = same_org? && (own_comment? || admin_or_investigator?)
  def destroy? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve
      visible_incident_ids = IncidentPolicy::Scope.new(user, Incident).resolve.pluck(:id)
      scope.where(incident_id: visible_incident_ids)
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

  def own_comment?
    record.author_id == user.id
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
