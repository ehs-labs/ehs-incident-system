class AttachmentPolicy < ApplicationPolicy
  def index?   = visible?
  def show?    = visible?
  def create?  = same_org? && incident_updatable?
  def update?  = create?
  def destroy? = create?

  class Scope < ApplicationPolicy::Scope
    def resolve
      visible_incident_ids = IncidentPolicy::Scope.new(user, Incident).resolve.pluck(:id)
      scope.where(record_type: "Incident", record_id: visible_incident_ids, name: "photos")
    end
  end

  private

  def incident
    @incident ||= case record
    when Incident
                    record
    when ActiveStorage::Attachment
                    record.record_type == "Incident" ? Incident.find_by(id: record.record_id) : nil
    end
  end

  def same_org?
    incident&.organization_id == user.organization_id
  end

  def visible?
    return false unless incident
    IncidentPolicy.new(user, incident).show?
  end

  def incident_updatable?
    return false unless incident
    IncidentPolicy.new(user, incident).update?
  end
end
