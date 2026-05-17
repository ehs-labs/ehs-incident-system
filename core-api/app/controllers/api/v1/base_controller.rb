module Api
  module V1
    class BaseController < ActionController::API
      include Pundit::Authorization
      include ActionController::Cookies   # needed for refresh-cookie flow

      before_action :authenticate_user!
      before_action :set_current

      rescue_from Pundit::NotAuthorizedError, with: :forbidden
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid,  with: :unprocessable
      rescue_from AASM::InvalidTransition,      with: :unprocessable_transition

      private

      def set_current
        Current.user = current_user if current_user
      end

      def forbidden(_e)
        render_problem(403, "Forbidden", "You do not have permission for this action")
      end

      def not_found(_e)
        render_problem(404, "Not found", "Resource not found")
      end

      def unprocessable(e)
        errors = e.record.errors.map do |err|
          { pointer: "/data/attributes/#{err.attribute}", detail: err.full_message }
        end
        render_problem(422, "Validation failed", "One or more attributes are invalid", errors: errors)
      end

      def unprocessable_transition(e)
        render_problem(422, "Invalid state transition", e.message)
      end

      def render_problem(status, title, detail, errors: nil)
        body = { type: "about:blank", title: title, status: status, detail: detail }
        body[:errors] = errors if errors
        render json: body, status: status, content_type: "application/problem+json"
      end

      def pagination_link_header(collection)
        return if collection.respond_to?(:total_pages) && collection.total_pages.nil?
        # kaminari pagination
        return unless collection.respond_to?(:current_page)

        urls = {}
        urls[:first] = pagination_url(1) unless collection.first_page?
        urls[:prev]  = pagination_url(collection.prev_page) if collection.prev_page
        urls[:next]  = pagination_url(collection.next_page) if collection.next_page
        urls[:last]  = pagination_url(collection.total_pages) unless collection.last_page?

        response.headers["Link"] = urls.map { |rel, url| "<#{url}>; rel=\"#{rel}\"" }.join(", ")
        response.headers["X-Total-Count"] = collection.total_count.to_s
      end

      def pagination_url(page)
        url_for(request.query_parameters.merge(page: page))
      end
    end
  end
end
