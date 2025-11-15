# frozen_string_literal: true

# ユーザーパスワード情報のバリデーション共通モジュール
# WEB版会員登録、SSO版会員登録、RP向けAPIで共通利用
module ValidatableUserPassword
  extend ActiveSupport::Concern

  included do
    attr_accessor :password, :password_confirmation

    # パスワード
    validates :password,
              presence: { message: 'パスワードを入力してください' },
              length: { minimum: 8, maximum: 128, message: 'パスワードは8文字以上で入力してください' }

    # スペースのみのパスワードを禁止
    validate :password_not_only_spaces

    # パスワード（確認）
    validates :password_confirmation,
              presence: { message: 'パスワード（確認のため再入力）を入力してください' }

    # パスワード一致チェック
    validates :password,
              confirmation: { message: 'パスワードと再入力パスワードが一致しません' }
  end

  private

  # パスワードがスペースのみでないことを検証
  def password_not_only_spaces
    return if password.blank?

    if password.strip.empty?
      errors.add(:password, 'パスワードは8文字以上で入力してください')
    end
  end
end
