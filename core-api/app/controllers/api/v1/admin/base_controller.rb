module Api
  module V1
    module Admin
      class BaseController < Api::V1::BaseController
        before_action :require_admin!

        private

        def require_admin!
          authorize :admin_access, :access?, policy_class: AdminAccessPolicy
        end
      end
    end
  end
end
