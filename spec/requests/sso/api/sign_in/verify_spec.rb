# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /sso/api/sign_in/verify", type: :request do
  let!(:user) { create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123') }

  describe "正常系" do
    before do
      user.generate_mail_authentication_code!
    end

    context "login_challengeなし（通常WEB）" do
      it "ログイン完了してauth_tokenが返される" do
        temp_token = JWT.encode(
          { user_id: user.id, exp: 10.minutes.from_now.to_i, purpose: 'temp_auth' },
          Rails.application.secret_key_base
        )

        post '/sso/api/sign_in/verify', params: {
          temp_token: temp_token,
          auth_code: user.mail_authentication_code
        }, as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['auth_token']).to be_present
        expect(json['status']).to eq('authenticated')
        expect(json['flow_type']).to eq('web')
        expect(json['redirect_to']).to eq('/users/profile')
      end
    end

    context "login_challengeあり（OAuth2フロー）" do
      it "Hydraリダイレクト先が返される" do
        # HydraService.accept_login_requestをモック
        allow(HydraService).to receive(:accept_login_request)
          .and_return('https://hydra.example.com/oauth2/auth?...')

        temp_token = JWT.encode(
          { user_id: user.id, exp: 10.minutes.from_now.to_i, purpose: 'temp_auth' },
          Rails.application.secret_key_base
        )

        post '/sso/api/sign_in/verify', params: {
          temp_token: temp_token,
          auth_code: user.mail_authentication_code,
          login_challenge: 'test_challenge_12345'
        }, as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['auth_token']).to be_present
        expect(json['status']).to eq('authenticated')
        expect(json['flow_type']).to eq('oauth2')
        expect(json['hydra_redirect']).to be_present
      end
    end
  end

  describe "異常系" do
    context "認証コードが間違っている場合" do
      before do
        user.generate_mail_authentication_code!
      end

      it "検証エラーが返される" do
        temp_token = JWT.encode(
          { user_id: user.id, exp: 10.minutes.from_now.to_i, purpose: 'temp_auth' },
          Rails.application.secret_key_base
        )

        post '/sso/api/sign_in/verify', params: {
          temp_token: temp_token,
          auth_code: 'wrong_code'
        }, as: :json

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json['error']).to be_present
      end
    end
  end
end
