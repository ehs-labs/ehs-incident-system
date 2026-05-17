# Backing table for devise-jwt revocations. On logout, the JTI of the access
# token is inserted here; every request rejects tokens whose JTI is present.
class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  self.table_name = "jwt_denylist"
end
