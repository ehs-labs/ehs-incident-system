module Api
  module V1
    class WitnessesController < BaseController
      before_action :set_incident, only: %i[index create]
      before_action :set_witness,  only: %i[show update destroy]

      # GET /api/v1/incidents/:incident_id/witnesses
      def index
        authorize @incident, :show?
        scope = policy_scope(Witness).where(incident_id: @incident.id)
                                     .order(created_at: :asc)
                                     .page(params[:page]).per(params[:per_page] || 25)

        pagination_link_header(scope)
        render json: WitnessSerializer.new(scope.to_a).serializable_hash
      end

      # POST /api/v1/incidents/:incident_id/witnesses
      def create
        @witness = @incident.witnesses.new(witness_params)
        authorize @witness
        @witness.save!
        render json: WitnessSerializer.new(@witness).serializable_hash, status: :created
      end

      # GET /api/v1/witnesses/:id
      def show
        authorize @witness
        render json: WitnessSerializer.new(@witness).serializable_hash
      end

      # PATCH /api/v1/witnesses/:id
      def update
        authorize @witness
        @witness.update!(witness_params)
        render json: WitnessSerializer.new(@witness).serializable_hash
      end

      # DELETE /api/v1/witnesses/:id
      def destroy
        authorize @witness
        @witness.destroy!
        head :no_content
      end

      private

      def set_incident
        @incident = policy_scope(Incident).find(params[:incident_id])
      end

      def set_witness
        @witness = policy_scope(Witness).find(params[:id])
      end

      def witness_params
        params.require(:witness).permit(:name, :email, :phone, :statement)
      end
    end
  end
end
