# SignupTicket - 会員登録フロー管理
#
# メール確認先行型の会員登録フローで使用するチケット。
# メールアドレスとトークンを発行し、メール確認後にconfirmed_atを設定。
# Valkeyキャッシュと組み合わせて、パスワード・プロフィール情報を一時保存する。
class SignupTicket < ApplicationRecord
  # バリデーション
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # トークン生成（64文字の16進数ランダム文字列）
  def self.generate_token
    SecureRandom.hex(32)
  end

  # 有効期限チェック
  def expired?
    expires_at < Time.current
  end

  # メール確認済みか
  def confirmed?
    confirmed_at.present?
  end

  # 登録に使用可能か（メール確認済み かつ 有効期限内）
  def valid_for_signup?
    confirmed? && !expired?
  end
end
