FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
    name { "山田太郎" }
    
    trait :activated do
      activated_at { Time.current }
    end
    
    trait :with_activation_token do
      activation_token { SecureRandom.urlsafe_base64(32) }
      activation_expires_at { 24.hours.from_now }
    end
    
    trait :with_auth_code do
      auth_code { "123456" }
      auth_code_expires_at { 10.minutes.from_now }
    end
    
    trait :recently_logged_in do
      last_login_at { 1.hour.ago }
    end
    
    trait :long_time_no_login do
      last_login_at { 30.days.ago }
    end
  end
end