# frozen_string_literal: true

# Userモデルの作成・更新を担当するService
# 会員登録およびプロフィール更新の業務ロジックを管理
class UserService
  # 会員登録からUser作成
  # SignupServiceから呼び出される
  #
  # @param email [String] メールアドレス
  # @param password [String] 平文パスワード
  # @param profile [Hash] プロフィール情報（name, birth_date等）
  # @return [User, nil] 作成されたUserオブジェクト、失敗時はnil
  def self.create_from_signup(email:, password:, profile: {})
    User.create!(
      email: email,
      password: password,
      password_confirmation: password,
      **profile.symbolize_keys,
      activated_at: Time.current  # activated?はactivated_at.present?で判定
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UserService.create_from_signup failed: #{e.message}"
    nil
  end

  # プロフィール更新
  #
  # @param user [User] 更新対象のUserオブジェクト
  # @param profile [Hash] 更新するプロフィール情報
  # @return [Boolean] 更新成功時true、失敗時false
  def self.update_profile(user, profile)
    user.update!(profile.symbolize_keys)
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UserService.update_profile failed: #{e.message}"
    false
  end
end
