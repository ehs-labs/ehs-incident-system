module Api
  module V1
    class CorrectiveActionEventsController < BaseController
      def index
        action = policy_scope(CorrectiveAction).find(params[:corrective_action_id])
        authorize action, :index?, policy_class: CorrectiveActionEventPolicy

        events = action.events.order(:created_at)
        render json: CorrectiveActionEventSerializer.new(events.to_a).serializable_hash
      end
    end
  end
end
