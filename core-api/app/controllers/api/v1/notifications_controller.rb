module Api
  module V1
    class NotificationsController < BaseController
      def index;  render json: { data: [] }; end
      def show;   render json: { data: {} }; end
      def create; render json: { data: {} }, status: :created; end
      def update; render json: { data: {} }; end
      def destroy; head :no_content; end
    end
  end
end
