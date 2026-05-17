FactoryBot.define do
  factory :witness do
    incident
    sequence(:name) { |n| "Witness #{n}" }
    sequence(:email) { |n| "witness#{n}-#{SecureRandom.hex(2)}@example.com" }
    phone     { "+61400000000" }
    statement { "I saw what happened." }
  end
end
