# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /users/api/sign_up/profile", type: :request do
  let(:signup_ticket) { create(:signup_ticket, email: 'test@example.com', confirmed_at: Time.current) }

  before do
    # パスワードをキャッシュに保存
    CacheService.save_signup_cache(signup_ticket.token, 'password', 'password123')
  end

  describe "正常系" do
    it "有効なトークンとプロフィールで保存される" do
      post '/users/api/sign_up/profile', params: {
        token: signup_ticket.token,
        last_name: '山田',
        first_name: '太郎',
        last_kana_name: 'やまだ',
        first_kana_name: 'たろう',
        employment_status: 1,
        birth_date: '1990-01-01',
        gender_code: 1,
        phone_number: '09012345678',
        home_prefecture_code: 13,
        home_master_city_id: 131016,
        home_address_later: '1-1-1',
        workplace_name: '株式会社テスト',
        workplace_phone_number: '0312345678',
        workplace_prefecture_code: 13,
        workplace_master_city_id: 131016,
        workplace_address_later: '2-2-2'
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end
  end

  describe "異常系" do
    context "苗字が空の場合" do
      it "バリデーションエラーが返される" do
        post '/users/api/sign_up/profile', params: {
          token: signup_ticket.token,
          last_name: '',
          first_name: '太郎',
          last_kana_name: 'ヤマダ',
          first_kana_name: 'タロウ',
          employment_status: 1
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['last_name']).to be_present
      end
    end
  end
end
