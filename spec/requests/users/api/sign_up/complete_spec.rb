# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /users/api/sign_up/complete", type: :request do
  let(:signup_ticket) { create(:signup_ticket, email: 'newuser@example.com', confirmed_at: Time.current) }

  before do
    # パスワードとプロフィールをキャッシュに保存
    CacheService.save_signup_cache(signup_ticket.token, 'password', 'password123')
    CacheService.save_signup_cache(signup_ticket.token, 'profile', { 'name' => '山田太郎' })
  end

  describe "正常系" do
    it "User作成とログインが完了する" do
      post '/users/api/sign_up/complete', params: {
        token: signup_ticket.token
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['message']).to include('会員登録が完了しました')
      expect(json['redirect_to']).to eq('/profile')

      # Userが作成されているか確認
      expect(User.find_by(email: 'newuser@example.com')).to be_present
    end
  end

  describe "異常系" do
    context "無効なトークンの場合" do
      it "エラーが返される" do
        post '/users/api/sign_up/complete', params: {
          token: 'invalid_token'
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['base']).to be_present
      end
    end
  end
end
