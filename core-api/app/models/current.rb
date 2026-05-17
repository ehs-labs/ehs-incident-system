# Thread/request-local current state. Set in BaseController#set_current.
# Used by AASM callbacks (where we don't have direct controller access) to
# attribute outbox events to the acting user.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
