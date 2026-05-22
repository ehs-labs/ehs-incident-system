module Api
  module V1
    class CorrectiveActionsController < BaseController
      before_action :set_incident, only: %i[create], if: -> { params[:incident_id].present? }
      before_action :set_action,   only: %i[show update transition]

      # GET /api/v1/incidents/:incident_id/corrective_actions  (nested)
      # GET /api/v1/corrective_actions                         (flat, with filters)
      def index
        scope = policy_scope(CorrectiveAction).includes(:incident, :assignee, :created_by)

        scope = scope.where(incident_id: params[:incident_id])  if params[:incident_id].present?
        scope = scope.where(state: params[:state])              if params[:state].present?
        scope = scope.where(assignee_id: params[:assignee_id])  if params[:assignee_id].present?
        scope = scope.overdue                                   if params[:overdue].to_s == "true"

        scope = scope.order(due_date: :asc).page(params[:page]).per(params[:per_page] || 25)

        pagination_link_header(scope)
        render json: CorrectiveActionSerializer.new(scope.to_a).serializable_hash
      end

      # GET /api/v1/corrective_actions/:id
      def show
        authorize @action
        render json: CorrectiveActionSerializer.new(@action, include: %i[incident assignee created_by]).serializable_hash
      end

      # POST /api/v1/incidents/:incident_id/corrective_actions
      def create
        attrs = corrective_action_params
        note  = attrs.delete(:note)

        @action = CorrectiveAction.new(attrs.merge(
          incident_id:   @incident.id,
          created_by_id: current_user.id
        ))
        authorize @action

        ApplicationRecord.transaction do
          @action.save!
          @action.events.create!(
            event_name: "assigned",
            actor_id:   current_user.id,
            note:       note
          )
          @action.publish_assigned_event!
        end

        render json: CorrectiveActionSerializer.new(@action).serializable_hash, status: :created
      end

      # PATCH /api/v1/corrective_actions/:id
      def update
        authorize @action
        @action.update!(corrective_action_params)
        render json: CorrectiveActionSerializer.new(@action).serializable_hash
      end

      # POST /api/v1/corrective_actions/:id/transitions
      # Body: { event: "start" | "complete" | "verify" | "cancel", note?: string }
      def transition
        event = params[:event].to_s
        unless CorrectiveAction.aasm.events.map { |e| e.name.to_s }.include?(event)
          return render_problem(422, "Unknown event", "Event '#{event}' is not defined on CorrectiveAction")
        end

        authorize @action, "#{event}?"

        ApplicationRecord.transaction do
          @action.pending_note = params[:note].presence
          @action.send("#{event}!")
        end

        render json: CorrectiveActionSerializer.new(@action.reload).serializable_hash
      end

      private

      def set_incident
        @incident = policy_scope(Incident).find(params[:incident_id])
      end

      def set_action
        @action = policy_scope(CorrectiveAction).find(params[:id])
      end

      def corrective_action_params
        params.require(:corrective_action).permit(
          :title, :description, :due_date, :assignee_id, :note, evidence: []
        )
      end
    end
  end
end
