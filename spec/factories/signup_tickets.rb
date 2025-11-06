FactoryBot.define do
  factory :signup_ticket do
    sequence(:email) { |n| "signup#{n}@example.com" }
    token { SecureRandom.urlsafe_base64(48) } # 64文字
    expires_at { 24.hours.from_now }
    confirmed_at { nil }

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :with_login_challenge do
      # login_challengeはキャッシュに保存されるため、Factoryでは設定しない
      # テストコード側でCacheService.save_signup_cacheを使用
    end
  end
end
