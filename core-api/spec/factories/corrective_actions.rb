FactoryBot.define do
  factory :corrective_action do
    incident
    assignee   { association(:user, organization: incident.organization) }
    created_by { association(:user, :investigator, organization: incident.organization) }

    title       { "Inspect equipment" }
    description { "Walk the floor and verify safety guards." }
    due_date    { 7.days.from_now }
    state       { "open" }

    trait :in_progress do
      state { "in_progress" }
    end

    trait :done do
      state        { "done" }
      completed_at { 1.hour.ago }
    end

    trait :verified do
      state        { "verified" }
      completed_at { 2.hours.ago }
      verified_at  { 1.hour.ago }
    end

    trait :overdue do
      after(:create) { |a| a.update_column(:due_date, 1.day.ago) }
    end
  end
end
