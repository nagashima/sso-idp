# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserService do
  before do
    # テストデータクリーンアップ
    User.destroy_all
  end

  describe '.create_from_signup' do
    let(:email) { 'test@example.com' }
    let(:password) { 'password123' }
    let(:profile) do
      {
        name: '山田太郎',
        birth_date: '1990-01-01',
        phone_number: '090-1234-5678',
        address: '東京都渋谷区'
      }
    end

    context '有効なパラメータの場合' do
      it 'アクティベート済みのユーザーを作成する' do
        user = UserService.create_from_signup(
          email: email,
          password: password,
          profile: profile
        )

        expect(user).to be_persisted
        expect(user.email).to eq email
        expect(user.name).to eq '山田太郎'
        expect(user.birth_date).to eq Date.parse('1990-01-01')
        expect(user.phone_number).to eq '090-1234-5678'
        expect(user.address).to eq '東京都渋谷区'
        expect(user.activated?).to be true
        expect(user.activated_at).to be_within(1.second).of(Time.current)
      end

      it 'パスワードが正しく暗号化される' do
        user = UserService.create_from_signup(
          email: email,
          password: password,
          profile: profile
        )

        expect(user.password_digest).to be_present
        expect(user.authenticate(password)).to eq user
      end
    end

    context 'プロフィール情報なし（最小限）' do
      it 'emailとpasswordのみでユーザー作成できる' do
        user = UserService.create_from_signup(
          email: email,
          password: password,
          profile: { name: '山田太郎' }  # nameは必須
        )

        expect(user).to be_persisted
        expect(user.email).to eq email
        expect(user.name).to eq '山田太郎'
        expect(user.birth_date).to be_nil
        expect(user.phone_number).to be_nil
      end
    end

    context '無効なメールアドレスの場合' do
      it 'nilを返す' do
        user = UserService.create_from_signup(
          email: 'invalid_email',
          password: password,
          profile: profile
        )

        expect(user).to be_nil
      end

      it 'ログにエラーを記録する' do
        expect(Rails.logger).to receive(:error).with(/UserService.create_from_signup failed/)

        UserService.create_from_signup(
          email: 'invalid_email',
          password: password,
          profile: profile
        )
      end
    end

    context 'メールアドレス重複の場合' do
      before do
        User.create!(
          email: email,
          password: password,
          password_confirmation: password,
          name: '既存ユーザー',
          activated_at: Time.current
        )
      end

      it 'nilを返す' do
        user = UserService.create_from_signup(
          email: email,
          password: password,
          profile: profile
        )

        expect(user).to be_nil
      end
    end

    context 'パスワードが短すぎる場合' do
      it 'nilを返す' do
        user = UserService.create_from_signup(
          email: email,
          password: 'short',  # 8文字未満
          profile: profile
        )

        expect(user).to be_nil
      end
    end

    context 'nameが空の場合' do
      it 'nilを返す' do
        user = UserService.create_from_signup(
          email: email,
          password: password,
          profile: { name: '' }
        )

        expect(user).to be_nil
      end
    end
  end

  describe '.update_profile' do
    let!(:user) do
      User.create!(
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: '山田太郎',
        activated_at: Time.current
      )
    end

    context '有効なプロフィール情報の場合' do
      it 'プロフィールを更新してtrueを返す' do
        result = UserService.update_profile(user, {
          name: '山田花子',
          birth_date: '1995-05-05',
          phone_number: '080-9999-8888'
        })

        expect(result).to be true
        expect(user.reload.name).to eq '山田花子'
        expect(user.birth_date).to eq Date.parse('1995-05-05')
        expect(user.phone_number).to eq '080-9999-8888'
      end
    end

    context '無効なプロフィール情報の場合' do
      it 'falseを返す' do
        result = UserService.update_profile(user, {
          email: 'invalid_email'  # 無効なメールアドレス
        })

        expect(result).to be false
      end

      it 'ログにエラーを記録する' do
        expect(Rails.logger).to receive(:error).with(/UserService.update_profile failed/)

        UserService.update_profile(user, {
          email: 'invalid_email'
        })
      end
    end

    context '空のプロフィール情報の場合' do
      it 'trueを返す（更新なし）' do
        original_name = user.name

        result = UserService.update_profile(user, {})

        expect(result).to be true
        expect(user.reload.name).to eq original_name
      end
    end
  end
end
