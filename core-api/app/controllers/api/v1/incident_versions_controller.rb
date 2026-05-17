module Api
  module V1
    # GET /api/v1/incidents/:incident_id/versions
    #
    # Returns the PaperTrail audit trail for an incident. The parent incident
    # is loaded through Pundit scoping, so users who can't see the incident
    # get the same 404 they'd get from the show endpoint.
    class IncidentVersionsController < BaseController
      def index
        incident = policy_scope(Incident).find(params[:incident_id])
        authorize incident, :show?

        versions = incident.versions
                           .order(created_at: :asc)
                           .page(params[:page])
                           .per(params[:per_page] || 20)

        pagination_link_header(versions)

        users_by_id = User.where(id: versions.map(&:whodunnit).compact).index_by { |u| u.id.to_s }

        render json: VersionSerializer.new(versions.to_a, params: { users: users_by_id }).serializable_hash
      end
    end
  end
end
