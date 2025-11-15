# frozen_string_literal: true

module Users
  # ユーザープロフィール情報のForm Object
  # WEB版会員登録、SSO版会員登録、会員情報変更、RP向けAPIで共通利用
  class ProfileForm < Form
    include ValidatableUserProfile

    # Strong Parametersからの初期化（WEB専用）
    #
    # @param params [ActionController::Parameters] リクエストパラメータ
    # @return [Users::ProfileForm] 初期化されたFormオブジェクト
    def self.initialize_from_params(params)
      permitted = params.permit(
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
  end
end
