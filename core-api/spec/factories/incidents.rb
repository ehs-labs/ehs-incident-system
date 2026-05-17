FactoryBot.define do
  factory :incident do
    organization
    site          { association(:site, organization: organization) }
    reporter      { association(:user, organization: organization) }
    incident_type { "slip" }
    severity      { 3 }
    occurred_at   { 1.hour.ago }
    location      { "Hall A" }
    summary       { "Slip near the entrance" }
    description   { "A worker slipped on a wet surface near the main entrance." }
  end
end
