# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('app/services/hydra_client')

RSpec.describe "POST /sso/api/sign_up/complete", type: :request do
  let(:signup_ticket) { create(:signup_ticket, email: 'newuser@example.com', confirmed_at: Time.current, login_challenge: 'test_challenge_123') }

  before do
    # パスワードとプロフィールをキャッシュに保存
    CacheService.save_signup_cache(signup_ticket.token, 'password', 'password123')
    CacheService.save_signup_cache(signup_ticket.token, 'profile', { 'name' => '山田太郎' })
    CacheService.save_signup_cache(signup_ticket.token, 'login_challenge', 'test_challenge_123')
  end

  describe "正常系" do
    it "User作成とHydra連携が完了する" do
      # HydraServiceのモック
      allow(HydraService).to receive(:accept_login_request).and_return('https://hydra.example.com/redirect')

      post '/sso/api/sign_up/complete', params: {
        token: signup_ticket.token
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['hydra_redirect']).to eq('https://hydra.example.com/redirect')
      expect(json['flow_type']).to eq('oauth2')

      # Userが作成されているか確認
      expect(User.find_by(email: 'newuser@example.com')).to be_present

      # HydraServiceが呼ばれたか確認
      expect(HydraService).to have_received(:accept_login_request).with('test_challenge_123', anything)
    end
  end

  describe "異常系" do
    context "Hydraエラーの場合" do
      it "通常フローにフォールバックする" do
        # HydraServiceがエラーを返す
        allow(HydraService).to receive(:accept_login_request).and_raise(HydraError, 'Challenge expired')

        post '/sso/api/sign_up/complete', params: {
          token: signup_ticket.token
        }, as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['redirect_to']).to eq('/profile')
        expect(json['notice']).to include('RP側から再度ログインしてください')
      end
    end
  end
end
