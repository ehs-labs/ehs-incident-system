module Api
  module V1
    module Auth
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        # POST /api/v1/auth/signup
        # Body: { user: { email, password, name, organization_name }, site_name?, site_timezone? }
        #
        # Self-signup is gated by SIGNUP_ENABLED env var. A fresh signup creates
        # a new Organization with the user as its first admin and a default
        # Site so they can immediately submit an incident.
        def create
          unless ENV.fetch("SIGNUP_ENABLED", "true") == "true"
            return render_problem(403, "Signup disabled", "Self-signup is currently disabled. Ask an admin for an invitation.")
          end

          user = nil

          ApplicationRecord.transaction do
            org = Organization.create!(
              name: params.dig(:user, :organization_name).presence || "#{params.dig(:user, :name)}'s organization",
              slug: SecureRandom.hex(8)
            )

            site = Site.create!(
              organization: org,
              name: params[:site_name].presence || "Default site",
              timezone: params[:site_timezone].presence || "UTC"
            )

            user = User.new(
              email:                 params.dig(:user, :email),
              password:              params.dig(:user, :password),
              password_confirmation: params.dig(:user, :password) || params.dig(:user, :password_confirmation),
              name:                  params.dig(:user, :name),
              organization:          org,
              role:                  :admin
            )
            # Self-signup auto-confirms — friction-free for demo / recruiter use.
            # (Invited users still go through the email confirmation flow.)
            user.skip_confirmation!
            user.save!

            SiteMembership.create!(user: user, site: site)
          end

          sign_in(user)

          render json: {
            access_token: request.env["warden-jwt_auth.token"] || response.headers["Authorization"]&.sub(/^Bearer /, ""),
            user: UserSerializer.new(user).serializable_hash,
            message: "Account created. Check MailCatcher (http://localhost:1080 in dev) for the confirmation email."
          }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record)
        end

        private

        def respond_with(resource, _opts = {}); end  # overridden by create

        def render_validation_error(record)
          errors = record.errors.map do |err|
            { pointer: "/data/attributes/#{err.attribute}", detail: err.full_message }
          end
          render json: {
            type: "about:blank", title: "Validation failed", status: 422,
            detail: "One or more attributes are invalid", errors: errors
          }, status: :unprocessable_entity, content_type: "application/problem+json"
        end

        def render_problem(status, title, detail)
          render json: { type: "about:blank", title: title, status: status, detail: detail },
                 status: status, content_type: "application/problem+json"
        end
      end
    end
  end
end
