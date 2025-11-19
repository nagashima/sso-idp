# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthenticationLoggerService, type: :service do
  let(:user) { create(:user, email: 'test@example.com') }
  let(:relying_party) { create(:relying_party, name: 'Test RP') }
  let(:request) { double('Request', remote_ip: '192.168.1.100', user_agent: 'Mozilla/5.0', headers: {}) }

  describe '.log_sign_in_success' do
    context 'WEBログイン成功' do
      it 'データベースにログが保存される' do
        expect do
          AuthenticationLoggerService.log_sign_in_success(
            user: user,
            request: request,
            sign_in_type: :web
          )
        end.to change(AuthenticationLog, :count).by(1)

        log = AuthenticationLog.last
        expect(log.user).to eq(user)
        expect(log.sign_in_type).to eq('web')
        expect(log.success).to be true
        expect(log.failure_reason).to be_nil
        expect(log.identifier).to eq(user.email)
        expect(log.ip_address).to eq('192.168.1.100')
        expect(log.user_agent).to eq('Mozilla/5.0')
        expect(log.relying_party).to be_nil
      end

      it 'JSON形式でログ出力される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)

          expect(log_json['event']).to eq('sign_in_success')
          expect(log_json['user_id']).to eq(user.id)
          expect(log_json['email']).to eq(user.email)
          expect(log_json['sign_in_type']).to eq('web')
          expect(log_json['ip_address']).to eq('192.168.1.100')
          expect(log_json['timestamp']).to be_present
          expect(log_json['relying_party_id']).to be_nil
        end

        AuthenticationLoggerService.log_sign_in_success(
          user: user,
          request: request,
          sign_in_type: :web
        )
      end
    end

    context 'SSOログイン成功' do
      it 'RPと共にログが保存される' do
        expect do
          AuthenticationLoggerService.log_sign_in_success(
            user: user,
            request: request,
            sign_in_type: :sso,
            relying_party: relying_party
          )
        end.to change(AuthenticationLog, :count).by(1)

        log = AuthenticationLog.last
        expect(log.user).to eq(user)
        expect(log.sign_in_type).to eq('sso')
        expect(log.success).to be true
        expect(log.relying_party).to eq(relying_party)
      end

      it 'JSON形式でログ出力される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)

          expect(log_json['event']).to eq('sign_in_success')
          expect(log_json['sign_in_type']).to eq('sso')
          expect(log_json['relying_party_id']).to eq(relying_party.id)
        end

        AuthenticationLoggerService.log_sign_in_success(
          user: user,
          request: request,
          sign_in_type: :sso,
          relying_party: relying_party
        )
      end
    end
  end

  describe '.log_sign_in_failure' do
    context 'パスワード不一致' do
      it 'データベースにログが保存される' do
        expect do
          AuthenticationLoggerService.log_sign_in_failure(
            identifier: user.email,
            request: request,
            sign_in_type: :web,
            failure_reason: :password_mismatch,
            user: user
          )
        end.to change(AuthenticationLog, :count).by(1)

        log = AuthenticationLog.last
        expect(log.user).to eq(user)
        expect(log.sign_in_type).to eq('web')
        expect(log.success).to be false
        expect(log.failure_reason).to eq('password_mismatch')
        expect(log.identifier).to eq(user.email)
      end

      it 'JSON形式で警告ログが出力される' do
        expect(Rails.logger).to receive(:warn) do |log_message|
          log_json = JSON.parse(log_message)

          expect(log_json['event']).to eq('sign_in_failure')
          expect(log_json['user_id']).to eq(user.id)
          expect(log_json['identifier']).to eq(user.email)
          expect(log_json['sign_in_type']).to eq('web')
          expect(log_json['failure_reason']).to eq('password_mismatch')
          expect(log_json['timestamp']).to be_present
        end

        AuthenticationLoggerService.log_sign_in_failure(
          identifier: user.email,
          request: request,
          sign_in_type: :web,
          failure_reason: :password_mismatch,
          user: user
        )
      end
    end

    context 'ユーザーが見つからない' do
      it 'ユーザーなしでログが保存される' do
        expect do
          AuthenticationLoggerService.log_sign_in_failure(
            identifier: 'unknown@example.com',
            request: request,
            sign_in_type: :web,
            failure_reason: :user_not_found
          )
        end.to change(AuthenticationLog, :count).by(1)

        log = AuthenticationLog.last
        expect(log.user).to be_nil
        expect(log.failure_reason).to eq('user_not_found')
        expect(log.identifier).to eq('unknown@example.com')
      end
    end

    context '2FA失敗' do
      it 'データベースにログが保存される' do
        expect do
          AuthenticationLoggerService.log_sign_in_failure(
            identifier: user.email,
            request: request,
            sign_in_type: :sso,
            failure_reason: :two_factor_failed,
            user: user
          )
        end.to change(AuthenticationLog, :count).by(1)

        log = AuthenticationLog.last
        expect(log.failure_reason).to eq('two_factor_failed')
        expect(log.sign_in_type).to eq('sso')
      end
    end

    context '環境変数での制御' do
      it 'LOG_FAILED_SIGN_IN=falseの場合、ログが保存されない' do
        allow(ENV).to receive(:fetch).with('LOG_FAILED_SIGN_IN', 'true').and_return('false')

        expect do
          AuthenticationLoggerService.log_sign_in_failure(
            identifier: user.email,
            request: request,
            sign_in_type: :web,
            failure_reason: :password_mismatch,
            user: user
          )
        end.not_to change(AuthenticationLog, :count)
      end
    end
  end

  describe 'プロキシ経由のIPアドレス抽出' do
    context 'X-Forwarded-Forヘッダーがある場合' do
      let(:request) do
        double('Request',
               remote_ip: '10.0.0.1',
               user_agent: 'Mozilla/5.0',
               headers: { 'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 198.51.100.1' })
      end

      it '最初のIPアドレスが使用される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)
          expect(log_json['ip_address']).to eq('203.0.113.1')
        end

        AuthenticationLoggerService.log_sign_in_success(
          user: user,
          request: request,
          sign_in_type: :web
        )
      end
    end

    context 'X-Real-IPヘッダーがある場合' do
      let(:request) do
        double('Request',
               remote_ip: '10.0.0.1',
               user_agent: 'Mozilla/5.0',
               headers: { 'HTTP_X_REAL_IP' => '203.0.113.2' })
      end

      it 'X-Real-IPが使用される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)
          expect(log_json['ip_address']).to eq('203.0.113.2')
        end

        AuthenticationLoggerService.log_sign_in_success(
          user: user,
          request: request,
          sign_in_type: :web
        )
      end
    end

    context '特別なヘッダーがない場合' do
      it 'remote_ipが使用される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)
          expect(log_json['ip_address']).to eq('192.168.1.100')
        end

        AuthenticationLoggerService.log_sign_in_success(
          user: user,
          request: request,
          sign_in_type: :web
        )
      end
    end
  end
end
