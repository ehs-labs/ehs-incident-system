module Api
  module V1
    class IncidentsController < BaseController
      before_action :set_incident, only: %i[show update transition]

      # GET /api/v1/incidents
      def index
        scope = policy_scope(Incident).includes(:site, :reporter, :assignee)
        scope = scope.where(state: params[:state])       if params[:state].present?
        scope = scope.where(severity: params[:severity]) if params[:severity].present?
        scope = scope.where(site_id: params[:site_id])   if params[:site_id].present?
        scope = scope.search(params[:q])                 if params[:q].present?
        scope = scope.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 25)

        pagination_link_header(scope)
        render json: IncidentSerializer.new(scope.to_a).serializable_hash
      end

      # GET /api/v1/incidents/:id
      def show
        authorize @incident
        render json: IncidentSerializer.new(@incident, include: [:site, :reporter, :assignee]).serializable_hash
      end

      # POST /api/v1/incidents
      def create
        @incident = Incident.new(incident_params.merge(
          organization_id: current_user.organization_id,
          reporter_id:     current_user.id
        ))
        authorize @incident
        @incident.save!
        render json: IncidentSerializer.new(@incident).serializable_hash, status: :created
      end

      # PATCH /api/v1/incidents/:id
      def update
        authorize @incident
        @incident.update!(incident_params)
        render json: IncidentSerializer.new(@incident).serializable_hash
      end

      # POST /api/v1/incidents/:id/transitions
      # Body: { event: "submit" | "triage" | ... [, assignee_id: ..., severity: ...] }
      def transition
        event = params[:event].to_s
        unless Incident.aasm.events.map { |e| e.name.to_s }.include?(event)
          return render_problem(422, "Unknown event", "Event '#{event}' is not defined on Incident")
        end

        authorize @incident, "#{event}?"

        ApplicationRecord.transaction do
          @incident.assignee_id = params[:assignee_id] if params.key?(:assignee_id)
          @incident.severity    = params[:severity]    if params.key?(:severity)
          @incident.send("#{event}!")
        end

        render json: IncidentSerializer.new(@incident.reload).serializable_hash
      end

      private

      def set_incident
        @incident = policy_scope(Incident).find(params[:id])
      end

      def incident_params
        params.require(:incident).permit(
          :site_id, :incident_type, :severity, :occurred_at,
          :location, :summary, :description, :root_cause, :assignee_id
        )
      end
    end
  end
end
