# frozen_string_literal: true

module Api
  module V1
    # RP向けAPI用のユーザー情報Form Object
    # POST/PATCH /api/v1/users で使用
    # email + password + profile + metadata を一括受け取り
    class UserForm < Form
      include ValidatableUserProfile
      include ValidatableUserPassword

      # API固有のフィールド
      attr_accessor :id, :email, :metadata

      # メールアドレス
      validates :email,
                format: { with: URI::MailTo::EMAIL_REGEXP, message: 'メールアドレスの形式が不正です' },
                allow_blank: true

      # Strong Parametersからの初期化（API専用）
      #
      # @param params [ActionController::Parameters] リクエストパラメータ
      # @return [Api::V1::UserForm] 初期化されたFormオブジェクト
      def self.initialize_from_api_params(params)
        permitted = params.permit(
          :id, :email, :metadata,
          :password, :password_confirmation,
          :last_name, :first_name, :has_middle_name, :middle_name,
          :last_kana_name, :first_kana_name,
          :birth_date, :gender_code, :gender_text,
          :phone_number,
          :home_is_address_selected_manually,
          :home_postal_code, :home_prefecture_code, :home_master_city_id,
          :home_address_town, :home_address_later,
          :employment_status,
          :workplace_name, :workplace_phone_number,
          :workplace_is_address_selected_manually,
          :workplace_postal_code, :workplace_prefecture_code, :workplace_master_city_id,
          :workplace_address_town, :workplace_address_later
        )
        new(permitted)
      end

      # Userモデルへの変換（profile + email + password）
      #
      # @return [Hash] Userモデルに渡す属性ハッシュ
      def to_user_attributes_with_auth
        attrs = to_user_attributes  # ValidatableUserProfileから継承
        attrs[:email] = normalize_email(email) if email.present?
        attrs[:password] = password if password.present?
        attrs[:password_confirmation] = password_confirmation if password_confirmation.present?
        attrs
      end
    end
  end
end
