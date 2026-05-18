module Api
  module V1
    class MeController < BaseController
      # GET /api/v1/me
      def show
        render json: me_payload(current_user)
      end

      # PATCH /api/v1/me
      def update
        current_user.update!(me_params)
        render json: me_payload(current_user.reload)
      end

      private

      def me_params
        params.require(:me).permit(:name)
      end

      def me_payload(user)
        org = user.organization
        sites = user.sites.where(organization_id: user.organization_id).pluck(:id, :name, :timezone).map do |id, name, tz|
          { id: id, name: name, timezone: tz }
        end

        {
          data: {
            type: "me",
            id:   user.id.to_s,
            attributes: {
              email:            user.email,
              name:             user.name,
              role:             user.role,
              organization: {
                id:   user.organization_id,
                slug: org&.slug,
                name: org&.name
              },
              sites:            sites
            }
          }
        }
      end
    end
  end
end
