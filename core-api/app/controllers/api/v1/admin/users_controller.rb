module Api
  module V1
    module Admin
      class UsersController < BaseController
        before_action :set_user, only: %i[show lock unlock destroy]

        # GET /api/v1/admin/users
        def index
          scope = policy_scope(::User).order(created_at: :desc)
          scope = scope.where(role: ::User.roles[params[:role]]) if params[:role].present? && ::User.roles.key?(params[:role])
          if params[:q].present?
            term = "%#{params[:q].to_s.downcase}%"
            scope = scope.where("LOWER(email) ILIKE ? OR LOWER(name) ILIKE ?", term, term)
          end
          scope = scope.page(params[:page]).per(params[:per_page] || 25)

          pagination_link_header(scope)
          render json: ::Admin::UserSerializer.new(scope.to_a).serializable_hash
        end

        # GET /api/v1/admin/users/:id
        def show
          authorize @user
          render json: ::Admin::UserSerializer.new(@user).serializable_hash
        end

        # POST /api/v1/admin/users/invite
        # Body: { user: { email, name, role, site_ids: [..] } }
        def invite
          authorize ::User.new(organization_id: current_user.organization_id), :invite?

          invited = ::User.invite!(
            { email: invite_params[:email],
              name:  invite_params[:name],
              role:  invite_params[:role],
              organization: current_user.organization },
            current_user
          )

          if invited.errors.empty?
            assign_sites(invited, Array(invite_params[:site_ids]))
            render json: ::Admin::UserSerializer.new(invited).serializable_hash, status: :created
          else
            errors = invited.errors.map { |e| { pointer: "/data/attributes/#{e.attribute}", detail: e.full_message } }
            render_problem(422, "Validation failed", "Could not invite user", errors: errors)
          end
        end

        # POST /api/v1/admin/users/:id/lock
        def lock
          authorize @user, :lock?
          @user.lock_access! unless @user.access_locked?
          render json: ::Admin::UserSerializer.new(@user.reload).serializable_hash
        end

        # POST /api/v1/admin/users/:id/unlock
        def unlock
          authorize @user, :unlock?
          @user.unlock_access! if @user.access_locked?
          render json: ::Admin::UserSerializer.new(@user.reload).serializable_hash
        end

        # DELETE /api/v1/admin/users/:id
        def destroy
          authorize @user, :destroy?
          @user.soft_delete!
          head :no_content
        end

        private

        def set_user
          @user = policy_scope(::User).find(params[:id])
        end

        def invite_params
          params.require(:user).permit(:email, :name, :role, site_ids: [])
        end

        def assign_sites(user, site_ids)
          return if site_ids.blank?
          org_site_ids = ::Site.where(organization_id: current_user.organization_id, id: site_ids).pluck(:id)
          org_site_ids.each { |sid| ::SiteMembership.find_or_create_by!(user: user, site_id: sid) }
        end
      end
    end
  end
end
