# frozen_string_literal: true

# UserSignInService: ログインフロー統括
# WEB版・SSO版ログインの共通処理を提供
class UserSignInService
  # Result Object パターン（SignupServiceと同じ設計思想）
  class Result
    attr_reader :user, :error_message, :error_reason

    def initialize(success:, user: nil, error_message: nil, error_reason: nil)
      @success = success
      @user = user
      @error_message = error_message
      @error_reason = error_reason  # ログ記録用: :user_not_found, :password_mismatch, etc.
    end

    def success?
      @success
    end
  end

  # 1段階目: メール・パスワード認証
  # 2FAコード生成・メール送信まで実行
  #
  # @param email [String] メールアドレス
  # @param password [String] パスワード
  # @return [Result] 処理結果
  def self.authenticate(email:, password:)
    # ユーザー検索
    user = User.find_by(email: email)
    return Result.new(
      success: false,
      error_message: '認証に失敗しました',
      error_reason: :user_not_found
    ) unless user

    # パスワード検証
    unless user.authenticate(password)
      return Result.new(
        success: false,
        user: user,  # ログ記録用にuserを返す
        error_message: '認証に失敗しました',
        error_reason: :password_mismatch
      )
    end

    # アクティベーション確認
    unless user.activated?
      return Result.new(
        success: false,
        user: user,
        error_message: 'アカウントが有効化されていません',
        error_reason: :user_not_activated
      )
    end

    # 2FAコード生成・送信
    user.generate_mail_authentication_code!
    UserMailer.auth_code_email(user).deliver_now

    Result.new(success: true, user: user)
  rescue StandardError => e
    Rails.logger.error "UserSignInService.authenticate failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Result.new(success: false, error_message: 'システムエラーが発生しました')
  end

  # 2段階目: 2FA検証＆ログイン完了
  # ログイン日時更新・認証コードクリアを実行
  #
  # @param user [User] 認証済みユーザー
  # @param auth_code [String] 認証コード
  # @return [Result] 処理結果
  def self.verify_and_complete(user:, auth_code:)
    # 認証コード検証
    unless user.mail_authentication_code_valid?(auth_code)
      return Result.new(
        success: false,
        user: user,
        error_message: '認証コードが正しくありません',
        error_reason: :two_factor_failed
      )
    end

    # ログイン完了処理
    user.update_last_sign_in!
    user.clear_mail_authentication_code!

    Result.new(success: true, user: user)
  rescue StandardError => e
    Rails.logger.error "UserSignInService.verify_and_complete failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Result.new(success: false, error_message: 'システムエラーが発生しました')
  end
end
