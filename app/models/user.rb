class User < ApplicationRecord
  # パスワード暗号化（encrypted_passwordカラムを使用）
  has_secure_password validations: false

  # 関連付け
  has_and_belongs_to_many :relying_parties, join_table: 'user_relying_parties'
  belongs_to :home_master_city, class_name: 'Master::City', foreign_key: 'home_master_city_id', optional: true
  belongs_to :workplace_master_city, class_name: 'Master::City', foreign_key: 'workplace_master_city_id', optional: true

  # バリデーション - 基本情報
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # バリデーション - 名前系（必須）
  validates :last_name, :first_name, :last_kana_name, :first_kana_name, presence: true
  validates :middle_name, presence: true, if: -> { has_middle_name == 1 }

  # バリデーション - 就労状況（必須）
  validates :employment_status, presence: true, inclusion: { in: [1, 2, 3] }

  # バリデーション - パスワード
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }

  # has_secure_passwordがencrypted_passwordカラムを使用するようにエイリアス設定
  alias_attribute :password_digest, :encrypted_password

  # メール認証コード生成（2段階認証用）
  def generate_mail_authentication_code!
    self.mail_authentication_code = SecureRandom.random_number(100000..999999)
    self.mail_authentication_expires_at = 10.minutes.from_now
    save!
  end

  # メール認証コード検証
  def mail_authentication_code_valid?(code)
    return false if mail_authentication_code.blank? || mail_authentication_expires_at.blank?
    return false if Time.current > mail_authentication_expires_at

    mail_authentication_code == code.to_i
  end

  # メール認証コードクリア
  def clear_mail_authentication_code!
    self.mail_authentication_code = nil
    self.mail_authentication_expires_at = nil
    save!
  end

  # 最終ログイン日時更新
  def update_last_sign_in!
    now = Time.current
    update!(last_sign_in_at: current_sign_in_at || now, current_sign_in_at: now)
  end

  # 最終ログイン日時の表示用メソッド
  def last_sign_in_display
    return "未ログイン" if last_sign_in_at.blank?

    time_ago = Time.current - last_sign_in_at
    case time_ago
    when 0..1.hour
      "#{time_ago.to_i / 60}分前"
    when 1.hour..1.day
      "#{time_ago.to_i / 3600}時間前"
    when 1.day..7.days
      "#{time_ago.to_i / 86400}日前"
    else
      last_sign_in_at.strftime("%Y/%m/%d")
    end
  end

  # フルネーム取得
  def full_name
    if has_middle_name == 1 && middle_name.present?
      "#{last_name} #{middle_name} #{first_name}"
    else
      "#{last_name} #{first_name}"
    end
  end

  # フルネーム（かな）取得
  def full_kana_name
    "#{last_kana_name} #{first_kana_name}"
  end
end