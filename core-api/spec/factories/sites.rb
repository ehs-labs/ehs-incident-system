FactoryBot.define do
  factory :site do
    organization
    sequence(:name) { |n| "Site #{n}" }
    timezone { "UTC" }
  end
end
