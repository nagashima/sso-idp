FactoryBot.define do
  factory :relying_party do
    sequence(:name) { |n| "Test RP #{n}" }
    sequence(:domain) { |n| "testdomain#{n}.example.com" }
    sequence(:api_key) { |n| "test_api_key_#{n}" }
    sequence(:api_secret) { |n| "test_api_secret_#{n}" }
  end
end
