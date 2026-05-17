# ============================================================================
# Devise configuration — full skeleton committed; tune in implementation.
#
# Highlights:
#   - JWT issuance/revocation via devise-jwt + denylist strategy
#   - lockable: 5 max attempts, 1 hour auto-unlock
#   - confirmable: email confirmation required before login
#   - invitable: admins invite users by email
# ============================================================================

Devise.setup do |config|
  config.mailer_sender = ENV.fetch("SMTP_FROM", "no-reply@ehs.local")

  require "devise/orm/active_record"

  # ----- General authentication --------------------------------------------
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage  = [:http_auth]
  config.stretches             = Rails.env.test? ? 1 : 12
  config.reconfirmable         = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length       = 8..128
  config.email_regexp          = /\A[^@\s]+@[^@\s]+\z/

  # ----- Lockable ----------------------------------------------------------
  config.lock_strategy     = :failed_attempts
  config.unlock_strategy   = :time
  config.maximum_attempts  = 5
  config.unlock_in         = 1.hour

  # ----- Confirmable -------------------------------------------------------
  config.allow_unconfirmed_access_for = 0.days
  config.confirm_within = 3.days
  config.reconfirmable  = true

  # ----- JWT ---------------------------------------------------------------
  config.jwt do |jwt|
    jwt.secret = ENV.fetch("JWT_SECRET")
    jwt.dispatch_requests = [
      ["POST", %r{^/api/v1/auth/login$}],
      ["POST", %r{^/api/v1/auth/signup$}]
    ]
    jwt.revocation_requests = [
      ["DELETE", %r{^/api/v1/auth/logout$}]
    ]
    jwt.expiration_time = 15.minutes.to_i   # short-lived; refresh cookie handles long sessions
  end
end
