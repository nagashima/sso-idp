class User < ApplicationRecord
  has_secure_password
  has_and_belongs_to_many :relying_parties

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }

  def generate_auth_code!
    self.auth_code = SecureRandom.random_number(100000..999999).to_s
    self.auth_code_expires_at = 10.minutes.from_now
    save!
  end

  def auth_code_valid?(code)
    return false if auth_code.blank? || auth_code_expires_at.blank?
    return false if Time.current > auth_code_expires_at
    
    auth_code == code
  end

  def clear_auth_code!
    self.auth_code = nil
    self.auth_code_expires_at = nil
    save!
  end

  # メール認証関連
  def activated?
    activated_at.present?
  end

  def generate_activation_token!
    self.activation_token = SecureRandom.urlsafe_base64(32)
    self.activation_expires_at = 24.hours.from_now
    save!
  end

  def activation_token_valid?(token)
    return false if activation_token.blank? || activation_expires_at.blank?
    return false if Time.current > activation_expires_at
    
    activation_token == token
  end

  def activate!
    self.activated_at = Time.current
    self.activation_token = nil
    self.activation_expires_at = nil
    save!
  end

  # 最終ログイン日時更新
  def update_last_login!
    update_column(:last_login_at, Time.current)
  end

  # 最終ログイン日時の表示用メソッド
  def last_login_display
    return "未ログイン" if last_login_at.blank?
    
    time_ago = Time.current - last_login_at
    case time_ago
    when 0..1.hour
      "#{time_ago.to_i / 60}分前"
    when 1.hour..1.day
      "#{time_ago.to_i / 3600}時間前"
    when 1.day..7.days
      "#{time_ago.to_i / 86400}日前"
    else
      last_login_at.strftime("%Y/%m/%d")
    end
  end
end