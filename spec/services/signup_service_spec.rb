# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignupService, type: :service do
  let(:token) { 'valid_token_12345' }
  let(:email) { 'test@example.com' }
  let(:password) { 'encrypted_password_hash' }
  let(:profile) { { name: 'Test User', birth_date: '1990-01-01' } }
  let(:signup_ticket) { create(:signup_ticket, token: token, email: email, confirmed_at: Time.current) }
  let(:request) { double('Request', remote_ip: '127.0.0.1', user_agent: 'RSpec') }

  describe '.complete_registration' do
    context '正常系: 登録成功' do
      before do
        # SignupTicket作成
        signup_ticket

        # キャッシュデータ準備
        CacheService.save_signup_cache(token, 'password', password)
        CacheService.save_signup_cache(token, 'profile', profile)

        # AuthenticationLoggerServiceをモック
        allow(AuthenticationLoggerService).to receive(:log_user_registration)
      end

      it 'Userが作成される' do
        expect {
          SignupService.complete_registration(token: token, request: request)
        }.to change(User, :count).by(1)
      end

      it 'Result.success? が true' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.success?).to be true
      end

      it 'Result.user が返される' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.user).to be_a(User)
        expect(result.user.email).to eq(email)
      end

      it 'キャッシュが削除される' do
        SignupService.complete_registration(token: token, request: request)

        expect(CacheService.get_signup_cache(token, 'password')).to be_nil
        expect(CacheService.get_signup_cache(token, 'profile')).to be_nil
      end

      it 'SignupTicketが削除される' do
        SignupService.complete_registration(token: token, request: request)

        expect(SignupTicket.find_by(token: token)).to be_nil
      end

      it 'AuthenticationLoggerServiceが呼ばれる' do
        expect(AuthenticationLoggerService).to receive(:log_user_registration)
        SignupService.complete_registration(token: token, request: request)
      end
    end

    context '異常系: 無効なトークン' do
      it 'Result.success? が false' do
        result = SignupService.complete_registration(token: 'invalid_token', request: request)
        expect(result.success?).to be false
      end

      it 'エラーメッセージが返される' do
        result = SignupService.complete_registration(token: 'invalid_token', request: request)
        expect(result.error_message).to eq('無効なトークンです')
      end

      it 'Userが作成されない' do
        expect {
          SignupService.complete_registration(token: 'invalid_token', request: request)
        }.not_to change(User, :count)
      end
    end

    context '異常系: キャッシュデータなし' do
      before do
        signup_ticket
      end

      it 'Result.success? が false' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.success?).to be false
      end

      it 'エラーメッセージが返される' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.error_message).to eq('データが見つかりません')
      end
    end

    context '異常系: User作成失敗' do
      before do
        signup_ticket
        CacheService.save_signup_cache(token, 'password', password)
        CacheService.save_signup_cache(token, 'profile', profile)

        # UserService.create_from_signupが失敗するようモック
        allow(UserService).to receive(:create_from_signup).and_return(nil)
      end

      it 'Result.success? が false' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.success?).to be false
      end

      it 'エラーメッセージが返される' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.error_message).to eq('ユーザー作成に失敗しました')
      end
    end

    context '異常系: 予期しない例外' do
      before do
        signup_ticket
        CacheService.save_signup_cache(token, 'password', password)
        CacheService.save_signup_cache(token, 'profile', profile)

        # 例外発生をシミュレート
        allow(UserService).to receive(:create_from_signup).and_raise(StandardError, 'Database error')
      end

      it 'Result.success? が false' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.success?).to be false
      end

      it 'システムエラーメッセージが返される' do
        result = SignupService.complete_registration(token: token, request: request)
        expect(result.error_message).to eq('システムエラーが発生しました')
      end

      it 'エラーログが記録される' do
        expect(Rails.logger).to receive(:error).with(/SignupService.complete_registration failed/)
        expect(Rails.logger).to receive(:error) # バックトレース
        SignupService.complete_registration(token: token, request: request)
      end
    end
  end
end
