FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    # 名前系（必須）
    last_name { "山田" }
    first_name { "太郎" }
    last_kana_name { "やまだ" }
    first_kana_name { "たろう" }
    has_middle_name { 0 }

    # 生年月日と性別（必須）
    birth_date { Date.new(1990, 1, 1) }
    gender_code { 1 }

    # 電話番号（必須）
    phone_number { "090-1234-5678" }

    # 自宅住所（必須）
    home_is_address_selected_manually { 0 }
    home_postal_code { "1000001" }
    home_prefecture_code { 13 }
    home_master_city_id { 131016 }  # 東京都千代田区
    home_address_town { "千代田" }
    home_address_later { "1-1" }

    # 就労状況（必須: 1=就労中/2=求職中/3=その他）
    employment_status { 1 }

    # 勤務先情報（就労中の場合）
    workplace_name { "株式会社テスト" }
    workplace_phone_number { "03-1234-5678" }
    workplace_is_address_selected_manually { 0 }
    workplace_postal_code { "1000002" }
    workplace_prefecture_code { 13 }
    workplace_master_city_id { 131016 }  # 東京都千代田区
    workplace_address_town { "千代田" }
    workplace_address_later { "2-2" }

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