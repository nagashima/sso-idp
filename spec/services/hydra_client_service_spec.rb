# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HydraClientService, type: :service do
  let(:user) { create(:user, name: 'Test User', email: 'test@example.com') }
  let(:challenge) { 'test_challenge_12345' }

  describe '.accept_login_request' do
    context '正常系: ログイン承認成功' do
      let(:redirect_url) { 'https://hydra.example.com/oauth2/auth?...' }
      let(:hydra_response) { { 'redirect_to' => redirect_url } }

      before do
        allow(HydraAdminClient).to receive(:accept_login_request)
          .with(challenge, user.id.to_s)
          .and_return(hydra_response)
      end

      it 'redirect_to URLが返される' do
        result = HydraClientService.accept_login_request(challenge, user.id)
        expect(result).to eq(redirect_url)
      end

      it 'HydraAdminClientが呼ばれる' do
        expect(HydraAdminClient).to receive(:accept_login_request)
          .with(challenge, user.id.to_s)
        HydraClientService.accept_login_request(challenge, user.id)
      end
    end

    context '異常系: HydraError発生' do
      before do
        allow(HydraAdminClient).to receive(:accept_login_request)
          .and_raise(HydraError, 'Challenge expired')
      end

      it 'HydraErrorがraiseされる' do
        expect {
          HydraClientService.accept_login_request(challenge, user.id)
        }.to raise_error(HydraError, 'Challenge expired')
      end

      it 'エラーログが記録される' do
        expect(Rails.logger).to receive(:error).with(/HydraClientService.accept_login_request failed/)
        expect {
          HydraClientService.accept_login_request(challenge, user.id)
        }.to raise_error(HydraError)
      end
    end

    context '異常系: 予期しない例外' do
      before do
        allow(HydraAdminClient).to receive(:accept_login_request)
          .and_raise(StandardError, 'Network error')
      end

      it 'HydraErrorに変換される' do
        expect {
          HydraClientService.accept_login_request(challenge, user.id)
        }.to raise_error(HydraError, 'Network error')
      end

      it 'エラーログが記録される' do
        expect(Rails.logger).to receive(:error).with(/unexpected error/)
        expect {
          HydraClientService.accept_login_request(challenge, user.id)
        }.to raise_error(HydraError)
      end
    end
  end

  describe '.accept_consent_request' do
    let(:scopes) { %w[openid profile email] }

    context '正常系: 同意承認成功' do
      let(:redirect_url) { 'https://rp.example.com/callback?code=...' }
      let(:hydra_response) { { 'redirect_to' => redirect_url } }
      let(:expected_id_token) do
        {
          sub: user.id.to_s,
          email: user.email,
          name: user.name
        }
      end

      before do
        allow(HydraAdminClient).to receive(:accept_consent_request)
          .with(challenge, scopes, expected_id_token)
          .and_return(hydra_response)
      end

      it 'redirect_to URLが返される' do
        result = HydraClientService.accept_consent_request(challenge, user, scopes)
        expect(result).to eq(redirect_url)
      end

      it 'HydraAdminClientが正しい引数で呼ばれる' do
        expect(HydraAdminClient).to receive(:accept_consent_request)
          .with(challenge, scopes, expected_id_token)
        HydraClientService.accept_consent_request(challenge, user, scopes)
      end
    end

    context '異常系: HydraError発生' do
      before do
        allow(HydraAdminClient).to receive(:accept_consent_request)
          .and_raise(HydraError, 'Invalid consent challenge')
      end

      it 'HydraErrorがraiseされる' do
        expect {
          HydraClientService.accept_consent_request(challenge, user, scopes)
        }.to raise_error(HydraError, 'Invalid consent challenge')
      end

      it 'エラーログが記録される' do
        expect(Rails.logger).to receive(:error).with(/HydraClientService.accept_consent_request failed/)
        expect {
          HydraClientService.accept_consent_request(challenge, user, scopes)
        }.to raise_error(HydraError)
      end
    end

    context '異常系: 予期しない例外' do
      before do
        allow(HydraAdminClient).to receive(:accept_consent_request)
          .and_raise(StandardError, 'Connection timeout')
      end

      it 'HydraErrorに変換される' do
        expect {
          HydraClientService.accept_consent_request(challenge, user, scopes)
        }.to raise_error(HydraError, 'Connection timeout')
      end

      it 'エラーログが記録される' do
        expect(Rails.logger).to receive(:error).with(/unexpected error/)
        expect {
          HydraClientService.accept_consent_request(challenge, user, scopes)
        }.to raise_error(HydraError)
      end
    end
  end
end
