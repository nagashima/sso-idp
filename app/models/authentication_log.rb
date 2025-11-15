class AuthenticationLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :relying_party, optional: true

  # sign_in_typeの定数定義
  SIGN_IN_TYPES = {
    web: 'web',
    sso: 'sso'
  }.freeze

  # failure_reasonの定数定義
  FAILURE_REASONS = {
    password_mismatch: 'password_mismatch',
    user_not_found: 'user_not_found',
    two_factor_failed: 'two_factor_failed',
    account_locked: 'account_locked'
  }.freeze

  # バリデーション
  validates :sign_in_type, presence: true, inclusion: { in: SIGN_IN_TYPES.values }
  validates :ip_address, presence: true
  validates :occurred_at, presence: true
  validates :success, inclusion: { in: [true, false] }
  validates :failure_reason, inclusion: { in: FAILURE_REASONS.values }, allow_nil: true

  # スコープ
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :web_sign_in, -> { where(sign_in_type: SIGN_IN_TYPES[:web]) }
  scope :sso_sign_in, -> { where(sign_in_type: SIGN_IN_TYPES[:sso]) }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_relying_party, ->(rp) { where(relying_party: rp) }

  # ユーザー情報の取得（ゲストユーザー対応）
  def user_identifier
    return user.email if user.present?
    return identifier if identifier.present?
    "unknown:#{ip_address}"
  end

  # sign_in_typeの日本語名
  def sign_in_type_name
    case sign_in_type
    when 'web'
      'WEBログイン'
    when 'sso'
      'SSOログイン'
    else
      sign_in_type
    end
  end

  # 成功/失敗の日本語表示
  def success_status
    success? ? '成功' : '失敗'
  end

  # 失敗理由の日本語表示
  def failure_reason_name
    return nil if failure_reason.blank?

    case failure_reason
    when 'password_mismatch'
      'パスワード不一致'
    when 'user_not_found'
      'ユーザー不存在'
    when 'two_factor_failed'
      '2段階認証失敗'
    when 'account_locked'
      'アカウントロック'
    else
      failure_reason
    end
  end
end
