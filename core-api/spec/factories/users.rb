FactoryBot.define do
  factory :user do
    organization
    sequence(:email) { |n| "user#{n}-#{SecureRandom.hex(2)}@example.com" }
    sequence(:name)  { |n| "User #{n}" }
    role { :worker }
    password              { "P!ssw0rd1234" }
    password_confirmation { "P!ssw0rd1234" }
    confirmed_at          { Time.current }

    trait :investigator do
      role { :investigator }
    end

    trait :admin do
      role { :admin }
    end
  end
end
