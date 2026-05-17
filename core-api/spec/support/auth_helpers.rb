module AuthHelpers
  # Drops a JWT for the given user into the Authorization header.
  def auth_headers(user)
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { "Authorization" => "Bearer #{token}", "ACCEPT" => "application/json" }
  end
end

RSpec.configure do |c|
  c.include AuthHelpers, type: :request
end
