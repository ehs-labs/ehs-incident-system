module Api
  module V1
    module Admin
      class SettingsController < BaseController
        # GET /api/v1/admin/settings
        def show
          setting = current_setting
          authorize setting, :show?
          render json: ::Admin::OrganizationSettingSerializer.new(setting).serializable_hash
        end

        # PATCH /api/v1/admin/settings
        # Body: { setting: { sla_overrides: { "1" => { "triage_seconds" => 7200 }, ... } } }
        def update
          setting = current_setting
          authorize setting, :update?
          setting.assign_attributes(setting_params)
          setting.save!
          render json: ::Admin::OrganizationSettingSerializer.new(setting).serializable_hash
        end

        private

        def current_setting
          ::OrganizationSetting.find_or_initialize_by(organization_id: current_user.organization_id)
        end

        def setting_params
          permitted = params.require(:setting).permit(sla_overrides: {})
          # Re-permit jsonb hash without losing the keys (Rails strong_params drops bare hashes
          # unless explicitly allowed). The `sla_overrides: {}` permits any nested keys.
          permitted
        end
      end
    end
  end
end
