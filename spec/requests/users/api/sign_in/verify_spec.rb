# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /users/api/sign_in/verify", type: :request do
  let(:user) { create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123') }

  describe "正常系" do
    before do
      user.activate!
      user.generate_auth_code! # 認証コード生成
    end

    it "有効なtemp_tokenと認証コードでログイン完了" do
      # temp_token生成（AuthenticateControllerと同じロジック）
      temp_token = JWT.encode(
        {
          user_id: user.id,
          exp: 10.minutes.from_now.to_i,
          purpose: 'temp_auth'
        },
        Rails.application.secret_key_base
      )

      # POSTリクエスト送信
      post '/users/api/sign_in/verify', params: {
        temp_token: temp_token,
        auth_code: user.auth_code # DBに保存された認証コード
      }, as: :json

      # 検証
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['auth_token']).to be_present
      expect(json['status']).to eq('authenticated')
      expect(json['flow_type']).to eq('web')
      expect(json['redirect_to']).to eq('/profile')
    end
  end

  describe "異常系" do
    context "temp_tokenが無効な場合" do
      before do
        user.activate!
      end

      it "トークンエラーが返される" do
        post '/users/api/sign_in/verify', params: {
          temp_token: 'invalid_token',
          auth_code: '123456'
        }, as: :json

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json['error']).to be_present
      end
    end

    context "認証コードが間違っている場合" do
      before do
        user.activate!
        user.generate_auth_code!
      end

      it "検証エラーが返される" do
        temp_token = JWT.encode(
          { user_id: user.id, exp: 10.minutes.from_now.to_i, purpose: 'temp_auth' },
          Rails.application.secret_key_base
        )

        post '/users/api/sign_in/verify', params: {
          temp_token: temp_token,
          auth_code: 'wrong_code' # 間違った認証コード
        }, as: :json

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json['error']).to include('verification')
      end
    end
  end
end
