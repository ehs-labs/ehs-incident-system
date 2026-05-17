module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        respond_to :json
        skip_before_action :verify_signed_out_user, only: :destroy

        # POST /api/v1/auth/login
        # Body: { user: { email, password } }
        def create
          user = User.find_for_database_authentication(email: params.dig(:user, :email))
          unless user&.valid_password?(params.dig(:user, :password))
            return render_problem(401, "Invalid credentials", "Email or password incorrect")
          end
          return render_problem(403, "Account locked",    "Try again later")    if user.access_locked?
          return render_problem(403, "Email unconfirmed", "Check your inbox")    unless user.confirmed?
          return render_problem(403, "Account deleted",   "Contact your admin")  if user.deleted?

          sign_in(user)
          render_user_with_token(user)
        end

        # DELETE /api/v1/auth/logout
        def destroy
          if current_user
            sign_out(current_user)
          end
          head :no_content
        end

        # POST /api/v1/auth/refresh  (placeholder — relies on the issuer setting)
        def refresh
          render_problem(501, "Not implemented", "Refresh-token flow comes in v2; for MVP, re-login via /auth/login")
        end

        private

        def respond_with(resource, _opts = {})
          render_user_with_token(resource)
        end

        def respond_to_on_destroy
          head :no_content
        end

        def render_user_with_token(user)
          render json: {
            access_token: request.env["warden-jwt_auth.token"] || response.headers["Authorization"]&.sub(/^Bearer /, ""),
            user: UserSerializer.new(user).serializable_hash
          }
        end

        def render_problem(status, title, detail)
          render json: { type: "about:blank", title: title, status: status, detail: detail },
                 status: status, content_type: "application/problem+json"
        end
      end
    end
  end
end
