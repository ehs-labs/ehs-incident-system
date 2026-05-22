module Api
  module V1
    class AssignableUsersController < BaseController
      before_action :authorize_access!

      # GET /api/v1/assignable_users
      def index
        scope = ::User.active
                      .where(organization_id: current_user.organization_id, locked_at: nil)
                      .order(:name)

        if params[:q].present?
          term = "%#{params[:q].to_s.downcase}%"
          scope = scope.where("LOWER(email) ILIKE ? OR LOWER(name) ILIKE ?", term, term)
        end

        render json: AssignableUserSerializer.new(scope.to_a).serializable_hash
      end

      private

      def authorize_access!
        authorize :assignable_user_access, :access?, policy_class: AssignableUserAccessPolicy
      end
    end
  end
end
