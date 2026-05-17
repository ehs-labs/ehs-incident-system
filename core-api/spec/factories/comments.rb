FactoryBot.define do
  factory :comment do
    incident
    author { association(:user, organization: incident.organization) }
    body   { "This is a comment on the incident." }
  end
end
