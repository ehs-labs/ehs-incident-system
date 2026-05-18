module Api
  module V1
    module Admin
      class SitesController < BaseController
        before_action :set_site, only: %i[show update destroy]

        # GET /api/v1/admin/sites
        def index
          scope = policy_scope(::Site).order(:name).page(params[:page]).per(params[:per_page] || 50)
          pagination_link_header(scope)
          render json: SiteSerializer.new(scope.to_a).serializable_hash
        end

        # GET /api/v1/admin/sites/:id
        def show
          authorize @site
          render json: SiteSerializer.new(@site).serializable_hash
        end

        # POST /api/v1/admin/sites
        def create
          site = ::Site.new(site_params.merge(organization_id: current_user.organization_id))
          authorize site
          site.save!
          render json: SiteSerializer.new(site).serializable_hash, status: :created
        end

        # PATCH /api/v1/admin/sites/:id
        def update
          authorize @site
          @site.update!(site_params)
          render json: SiteSerializer.new(@site).serializable_hash
        end

        # DELETE /api/v1/admin/sites/:id
        def destroy
          authorize @site
          @site.destroy!
          head :no_content
        end

        private

        def set_site
          @site = policy_scope(::Site).find(params[:id])
        end

        def site_params
          params.require(:site).permit(:name, :timezone)
        end
      end
    end
  end
end
