module Api
  module V1
    # GET /api/v1/corrective_actions/:corrective_action_id/versions
    #
    # Audit trail for a corrective action. Visibility piggybacks on the
    # CorrectiveActionPolicy scope — users who can't see the row get a 404.
    class CorrectiveActionVersionsController < BaseController
      def index
        action = policy_scope(CorrectiveAction).find(params[:corrective_action_id])
        authorize action, :show?

        versions = action.versions
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
