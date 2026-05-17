module Api
  module V1
    module Auth
      class ConfirmationsController < Devise::ConfirmationsController
        respond_to :json
      end
    end
  end
end
