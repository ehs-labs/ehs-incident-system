module Api
  module V1
    class AttachmentsController < BaseController
      before_action :set_incident,   only: %i[index create]
      before_action :set_attachment, only: %i[destroy]

      # GET /api/v1/incidents/:incident_id/attachments
      def index
        authorize @incident, :show?
        scope = visible_attachments_scope
                  .where(record_id: @incident.id)
                  .includes(:blob)
                  .order(created_at: :asc)
                  .page(params[:page]).per(params[:per_page] || 25)

        pagination_link_header(scope)
        render json: AttachmentSerializer.new(scope.to_a).serializable_hash
      end

      # POST /api/v1/incidents/:incident_id/attachments
      # Multipart body: attachment[file]
      def create
        authorize @incident, :update?

        file = params.dig(:attachment, :file) || params[:file]
        unless file.respond_to?(:original_filename)
          return render_problem(422, "Missing file", "Expected multipart upload at attachment[file]")
        end

        @incident.photos.attach(file)
        attachment = @incident.photos.attachments.order(:created_at).last
        render json: AttachmentSerializer.new(attachment).serializable_hash, status: :created
      end

      # DELETE /api/v1/attachments/:id
      def destroy
        authorize @attachment, :destroy?, policy_class: AttachmentPolicy
        @attachment.purge
        head :no_content
      end

      private

      def set_incident
        @incident = policy_scope(Incident).find(params[:incident_id])
      end

      def set_attachment
        @attachment = ActiveStorage::Attachment.find(params[:id])
        # Guard against accessing attachments outside the user's visible
        # incidents. The Pundit authorize call below confirms updatability,
        # but a 404 on out-of-scope records mirrors policy_scope semantics
        # used elsewhere (a 403 would leak existence).
        raise ActiveRecord::RecordNotFound unless visible_attachments_scope
                                                    .where(id: @attachment.id).exists?
      end

      # ActiveStorage::Attachment is a Rails-internal class; pundit can't
      # resolve its policy via convention, so we apply AttachmentPolicy::Scope
      # explicitly here.
      def visible_attachments_scope
        AttachmentPolicy::Scope.new(current_user, ActiveStorage::Attachment).resolve
      end
    end
  end
end
