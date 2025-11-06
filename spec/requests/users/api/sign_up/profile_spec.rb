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
        name: '山田太郎'
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end
  end

  describe "異常系" do
    context "名前が空の場合" do
      it "バリデーションエラーが返される" do
        post '/users/api/sign_up/profile', params: {
          token: signup_ticket.token,
          name: ''
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['name']).to be_present
      end
    end
  end
end
