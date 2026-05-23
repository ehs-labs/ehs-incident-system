FactoryBot.define do
  factory :corrective_action_event do
    corrective_action
    actor { association(:user, organization: corrective_action.incident.organization) }
    event_name { "assigned" }
    note { nil }
  end
end
