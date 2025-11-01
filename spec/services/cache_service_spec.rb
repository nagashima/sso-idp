# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CacheService do
  let(:token) { 'test_token_123' }
  let(:user_id) { 456 }

  before do
    # テスト前にキャッシュクリア
    Rails.cache.clear
  end

  describe '.save_signup_cache / .get_signup_cache' do
    it 'キャッシュに値を保存して取得できる' do
      value = 'test_value'
      CacheService.save_signup_cache(token, 'key1', value)

      expect(CacheService.get_signup_cache(token, 'key1')).to eq value
    end

    it '異なるキーで保存した値は干渉しない' do
      CacheService.save_signup_cache(token, 'key1', 'value1')
      CacheService.save_signup_cache(token, 'key2', 'value2')

      expect(CacheService.get_signup_cache(token, 'key1')).to eq 'value1'
      expect(CacheService.get_signup_cache(token, 'key2')).to eq 'value2'
    end

    it '存在しないキーを取得するとnilを返す' do
      expect(CacheService.get_signup_cache(token, 'nonexistent')).to be_nil
    end

    it 'Hash形式のデータを保存・取得できる' do
      profile = { name: '山田太郎', birth_date: '1990-01-01' }
      CacheService.save_signup_cache(token, 'profile', profile)

      expect(CacheService.get_signup_cache(token, 'profile')).to eq profile
    end

    it 'expires_inを指定できる' do
      CacheService.save_signup_cache(token, 'key1', 'value', expires_in: 1.hour)

      expect(CacheService.get_signup_cache(token, 'key1')).to eq 'value'
    end
  end

  describe '.get_signup_data' do
    context 'password と profile の両方が存在する場合' do
      before do
        CacheService.save_signup_cache(token, 'password', 'encrypted_password_123')
        CacheService.save_signup_cache(token, 'profile', { name: '山田太郎' })
      end

      it '両方のデータをHashで返す' do
        result = CacheService.get_signup_data(token)

        expect(result).to be_a(Hash)
        expect(result[:password]).to eq 'encrypted_password_123'
        expect(result[:profile]).to eq({ name: '山田太郎' })
      end
    end

    context 'password のみ存在する場合' do
      before do
        CacheService.save_signup_cache(token, 'password', 'encrypted_password_123')
      end

      it 'nilを返す（データ不完全）' do
        expect(CacheService.get_signup_data(token)).to be_nil
      end
    end

    context 'profile のみ存在する場合' do
      before do
        CacheService.save_signup_cache(token, 'profile', { name: '山田太郎' })
      end

      it 'nilを返す（データ不完全）' do
        expect(CacheService.get_signup_data(token)).to be_nil
      end
    end

    context 'どちらも存在しない場合' do
      it 'nilを返す' do
        expect(CacheService.get_signup_data(token)).to be_nil
      end
    end
  end

  describe '.delete_signup_cache' do
    before do
      CacheService.save_signup_cache(token, 'password', 'encrypted_password_123')
      CacheService.save_signup_cache(token, 'profile', { name: '山田太郎' })
      CacheService.save_signup_cache(token, 'login_challenge', 'challenge_xyz')
    end

    it 'トークンに紐づく全キャッシュを削除する' do
      CacheService.delete_signup_cache(token)

      expect(CacheService.get_signup_cache(token, 'password')).to be_nil
      expect(CacheService.get_signup_cache(token, 'profile')).to be_nil
      expect(CacheService.get_signup_cache(token, 'login_challenge')).to be_nil
    end

    it '異なるトークンのキャッシュは削除しない' do
      other_token = 'other_token_456'
      CacheService.save_signup_cache(other_token, 'password', 'other_password')

      CacheService.delete_signup_cache(token)

      expect(CacheService.get_signup_cache(other_token, 'password')).to eq 'other_password'
    end
  end

  describe '.save_user_cache / .get_user_cache / .delete_user_cache' do
    it 'ユーザーIDベースでキャッシュを保存・取得・削除できる' do
      CacheService.save_user_cache(user_id, 'draft', { data: 'test' })

      expect(CacheService.get_user_cache(user_id, 'draft')).to eq({ data: 'test' })

      CacheService.delete_user_cache(user_id, 'draft')

      expect(CacheService.get_user_cache(user_id, 'draft')).to be_nil
    end

    it '異なるユーザーIDのキャッシュは干渉しない' do
      CacheService.save_user_cache(user_id, 'key1', 'value1')
      CacheService.save_user_cache(999, 'key1', 'value2')

      expect(CacheService.get_user_cache(user_id, 'key1')).to eq 'value1'
      expect(CacheService.get_user_cache(999, 'key1')).to eq 'value2'
    end
  end
end
