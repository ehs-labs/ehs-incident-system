module Api
  module V1
    class CommentsController < BaseController
      before_action :set_incident, only: %i[index create]
      before_action :set_comment,  only: %i[show update destroy]

      # GET /api/v1/incidents/:incident_id/comments
      def index
        authorize @incident, :show?
        scope = policy_scope(Comment).where(incident_id: @incident.id)
                                     .includes(:author)
                                     .order(created_at: :asc)
                                     .page(params[:page]).per(params[:per_page] || 25)

        pagination_link_header(scope)
        render json: CommentSerializer.new(scope.to_a, include: [ :author ]).serializable_hash
      end

      # POST /api/v1/incidents/:incident_id/comments
      def create
        @comment = @incident.comments.new(comment_params.merge(author_id: current_user.id))
        authorize @comment
        @comment.save!
        render json: CommentSerializer.new(@comment).serializable_hash, status: :created
      end

      # GET /api/v1/comments/:id
      def show
        authorize @comment
        render json: CommentSerializer.new(@comment).serializable_hash
      end

      # PATCH /api/v1/comments/:id
      def update
        authorize @comment
        @comment.update!(comment_params)
        render json: CommentSerializer.new(@comment).serializable_hash
      end

      # DELETE /api/v1/comments/:id
      def destroy
        authorize @comment
        @comment.destroy!
        head :no_content
      end

      private

      def set_incident
        @incident = policy_scope(Incident).find(params[:incident_id])
      end

      def set_comment
        @comment = policy_scope(Comment).find(params[:id])
      end

      def comment_params
        params.require(:comment).permit(:body)
      end
    end
  end
end
