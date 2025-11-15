FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    # 名前系（必須）
    last_name { "山田" }
    first_name { "太郎" }
    last_kana_name { "ヤマダ" }
    first_kana_name { "タロウ" }
    has_middle_name { 0 }

    # 就労状況（必須: 1=就労中/2=求職中/3=その他）
    employment_status { 1 }
    
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