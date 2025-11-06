# frozen_string_literal: true

# Valkeyキャッシュ操作を担当するService
# 会員登録フロー中の一時データ保存・取得・削除を管理
class CacheService
  # 会員登録用キャッシュ保存（tokenベース）
  #
  # @param token [String] SignupTicketのトークン
  # @param key [String] キャッシュキー（password, profile, login_challenge等）
  # @param value [Object] 保存する値
  # @param expires_in [ActiveSupport::Duration] 有効期限（デフォルト: 24時間）
  # @return [Boolean] 保存成功/失敗
  def self.save_signup_cache(token, key, value, expires_in: 24.hours)
    Rails.cache.write("signup:#{token}:#{key}", value, expires_in: expires_in)
  end

  # 会員登録用キャッシュ取得（tokenベース）
  #
  # @param token [String] SignupTicketのトークン
  # @param key [String] キャッシュキー
  # @return [Object, nil] 保存されている値、存在しない場合はnil
  def self.get_signup_cache(token, key)
    Rails.cache.read("signup:#{token}:#{key}")
  end

  # 会員登録用キャッシュ一括取得（password + profile）
  # 登録完了時に全データを取得するために使用
  #
  # @param token [String] SignupTicketのトークン
  # @return [Hash, nil] { password: String, profile: Hash }、データが不完全な場合はnil
  def self.get_signup_data(token)
    password = get_signup_cache(token, 'password')
    profile = get_signup_cache(token, 'profile')

    return nil if password.nil? || profile.nil?

    { password: password, profile: profile }
  end

  # 会員登録用キャッシュ削除（tokenに紐づく全データ）
  # 登録完了時またはトークン期限切れ時に使用
  #
  # @param token [String] SignupTicketのトークン
  # @return [Integer] 削除したキー数
  def self.delete_signup_cache(token)
    Rails.cache.delete_matched("signup:#{token}:*")
  end

  # ユーザー単位のキャッシュ保存（将来的に使用）
  #
  # @param user_id [Integer] ユーザーID
  # @param key [String] キャッシュキー
  # @param value [Object] 保存する値
  # @param expires_in [ActiveSupport::Duration] 有効期限（デフォルト: 30分）
  # @return [Boolean] 保存成功/失敗
  def self.save_user_cache(user_id, key, value, expires_in: 30.minutes)
    Rails.cache.write("user:#{user_id}:#{key}", value, expires_in: expires_in)
  end

  # ユーザー単位のキャッシュ取得（将来的に使用）
  #
  # @param user_id [Integer] ユーザーID
  # @param key [String] キャッシュキー
  # @return [Object, nil] 保存されている値、存在しない場合はnil
  def self.get_user_cache(user_id, key)
    Rails.cache.read("user:#{user_id}:#{key}")
  end

  # ユーザー単位のキャッシュ削除（将来的に使用）
  #
  # @param user_id [Integer] ユーザーID
  # @param key [String] キャッシュキー
  # @return [Boolean] 削除成功/失敗
  def self.delete_user_cache(user_id, key)
    Rails.cache.delete("user:#{user_id}:#{key}")
  end
end
