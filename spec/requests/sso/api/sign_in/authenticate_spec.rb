# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /sso/api/sign_in/authenticate", type: :request do
  let!(:user) { create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123') }

  describe "正常系" do
    context "login_challengeなし（通常WEB）" do
      it "temp_tokenが返される" do
        post '/sso/api/sign_in/authenticate', params: {
          email: 'test@example.com',
          password: 'password123'
        }, as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['temp_token']).to be_present
        expect(json['status']).to eq('awaiting_2fa')
        expect(json['flow_type']).to eq('web')
      end
    end

    context "login_challengeあり（OAuth2フロー）" do
      it "temp_tokenとlogin_challengeが返される" do
        post '/sso/api/sign_in/authenticate', params: {
          email: 'test@example.com',
          password: 'password123',
          login_challenge: 'test_challenge_12345'
        }, as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['temp_token']).to be_present
        expect(json['status']).to eq('awaiting_2fa')
        expect(json['flow_type']).to eq('oauth2')
        expect(json['login_challenge']).to eq('test_challenge_12345')
      end
    end
  end

  describe "異常系" do
    context "メールアドレスが空の場合" do
      it "バリデーションエラーが返される" do
        post '/sso/api/sign_in/authenticate', params: {
          email: '',
          password: 'password123'
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['email']).to be_present
      end
    end
  end
end
