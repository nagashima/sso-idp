# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthenticationLoggerService, type: :service do
  let(:user) { create(:user, name: 'Test User', email: 'test@example.com') }
  let(:request) { double('Request', remote_ip: '192.168.1.100', user_agent: 'Mozilla/5.0', headers: {}) }

  describe '.log_user_registration' do
    it 'JSON形式でログ出力される' do
      expect(Rails.logger).to receive(:info) do |log_message|
        log_json = JSON.parse(log_message)

        expect(log_json['event']).to eq('user_registration')
        expect(log_json['user_id']).to eq(user.id)
        expect(log_json['email']).to eq(user.email)
        expect(log_json['login_method']).to eq('normal')
        expect(log_json['ip_address']).to eq('192.168.1.100')
        expect(log_json['user_agent']).to eq('Mozilla/5.0')
        expect(log_json['timestamp']).to be_present
      end

      AuthenticationLoggerService.log_user_registration(user, request)
    end

    it 'login_methodを指定できる' do
      expect(Rails.logger).to receive(:info) do |log_message|
        log_json = JSON.parse(log_message)
        expect(log_json['login_method']).to eq('sso_signup')
      end

      AuthenticationLoggerService.log_user_registration(user, request, login_method: 'sso_signup')
    end
  end

  describe '.log_login' do
    it 'JSON形式でログ出力される' do
      expect(Rails.logger).to receive(:info) do |log_message|
        log_json = JSON.parse(log_message)

        expect(log_json['event']).to eq('user_login')
        expect(log_json['user_id']).to eq(user.id)
        expect(log_json['email']).to eq(user.email)
        expect(log_json['login_method']).to eq('normal')
        expect(log_json['ip_address']).to eq('192.168.1.100')
        expect(log_json['user_agent']).to eq('Mozilla/5.0')
        expect(log_json['timestamp']).to be_present
      end

      AuthenticationLoggerService.log_login(user, request)
    end

    it 'login_methodを指定できる' do
      expect(Rails.logger).to receive(:info) do |log_message|
        log_json = JSON.parse(log_message)
        expect(log_json['login_method']).to eq('sso')
      end

      AuthenticationLoggerService.log_login(user, request, login_method: 'sso')
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

        AuthenticationLoggerService.log_user_registration(user, request)
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

        AuthenticationLoggerService.log_user_registration(user, request)
      end
    end

    context '特別なヘッダーがない場合' do
      it 'remote_ipが使用される' do
        expect(Rails.logger).to receive(:info) do |log_message|
          log_json = JSON.parse(log_message)
          expect(log_json['ip_address']).to eq('192.168.1.100')
        end

        AuthenticationLoggerService.log_user_registration(user, request)
      end
    end
  end
end
