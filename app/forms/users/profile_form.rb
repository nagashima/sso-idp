# frozen_string_literal: true

module Users
  # ユーザープロフィール情報のForm Object
  # WEB版会員登録、SSO版会員登録、会員情報変更、RP向けAPIで共通利用
  class ProfileForm < Form
    attr_accessor :last_name, :first_name, :has_middle_name, :middle_name,
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

    # 基本情報
    validates :last_name, presence: { message: '姓を入力してください' }
    validates :first_name, presence: { message: '名を入力してください' }
    validates :last_kana_name,
              presence: { message: '姓（かな）を入力してください' },
              format: { with: VALID_HIRAGANA_REGEX, message: '姓（かな）はひらがなで入力してください' }
    validates :first_kana_name,
              presence: { message: '名（かな）を入力してください' },
              format: { with: VALID_HIRAGANA_REGEX, message: '名（かな）はひらがなで入力してください' }

    # ミドルネーム（産後ケアRPより厳密化）
    validates :middle_name,
              presence: { message: 'ミドルネームを入力してください' },
              if: -> { has_middle_name == 1 }

    # 生年月日
    validates :birth_date, presence: { message: '生年月日を入力してください' }

    # 性別（SSO-IdP特有）
    validates :gender_code,
              presence: { message: '性別を選択してください' },
              inclusion: { in: [1, 2, 3, 4], message: '性別の選択が不正です' }
    validates :gender_text,
              presence: { message: '性別（自由記述）を入力してください' },
              if: -> { gender_code == 4 }

    # 電話番号（形式チェックなし、産後ケアRPと同じ）
    validates :phone_number,
              presence: { message: '携帯電話を入力してください' }

    # 自宅住所
    validates :home_postal_code,
              presence: { message: '郵便番号を入力してください' },
              format: { with: VALID_POSTAL_CODE_REGEX, message: '郵便番号の形式が不正です' },
              if: -> { home_is_address_selected_manually == 0 }
    validates :home_prefecture_code,
              presence: { message: '都道府県を選択してください' }
    validates :home_master_city_id,
              presence: { message: '市区町村を選択してください' }
    validates :home_address_later,
              presence: { message: '番地以降を入力してください' }

    # 就労状況（SSO-IdP特有）
    validates :employment_status,
              presence: { message: '就労状況を選択してください' },
              inclusion: { in: [1, 2, 3], message: '就労状況の選択が不正です' }

    # 勤務先情報（就労=1の場合のみ）
    validates :workplace_name,
              presence: { message: '勤務先名を入力してください' },
              if: -> { employment_status == 1 }
    validates :workplace_phone_number,
              presence: { message: '勤務先電話番号を入力してください' },
              if: -> { employment_status == 1 }
    validates :workplace_postal_code,
              presence: { message: '勤務先郵便番号を入力してください' },
              format: { with: VALID_POSTAL_CODE_REGEX, message: '勤務先郵便番号の形式が不正です' },
              if: -> { employment_status == 1 && workplace_is_address_selected_manually == 0 }
    validates :workplace_prefecture_code,
              presence: { message: '勤務先都道府県を選択してください' },
              if: -> { employment_status == 1 }
    validates :workplace_master_city_id,
              presence: { message: '勤務先市区町村を選択してください' },
              if: -> { employment_status == 1 }
    validates :workplace_address_later,
              presence: { message: '勤務先番地以降を入力してください' },
              if: -> { employment_status == 1 }

    # Strong Parametersからの初期化
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

    # Userモデルへの変換
    #
    # @return [Hash] Userモデルに渡す属性ハッシュ
    def to_user_attributes
      attributes = {
        last_name: last_name,
        first_name: first_name,
        has_middle_name: has_middle_name,
        middle_name: middle_name,
        last_kana_name: last_kana_name,
        first_kana_name: first_kana_name,
        birth_date: birth_date,
        gender_code: gender_code,
        gender_text: gender_text,
        phone_number: normalize_phone_number(phone_number),
        home_is_address_selected_manually: home_is_address_selected_manually,
        home_postal_code: normalize_postal_code(home_postal_code),
        home_prefecture_code: home_prefecture_code,
        home_master_city_id: home_master_city_id,
        home_address_town: home_address_town,
        home_address_later: home_address_later,
        employment_status: employment_status,
        workplace_name: workplace_name,
        workplace_phone_number: normalize_phone_number(workplace_phone_number),
        workplace_is_address_selected_manually: workplace_is_address_selected_manually,
        workplace_postal_code: normalize_postal_code(workplace_postal_code),
        workplace_prefecture_code: workplace_prefecture_code,
        workplace_master_city_id: workplace_master_city_id,
        workplace_address_town: workplace_address_town,
        workplace_address_later: workplace_address_later
      }

      # ミドルネームの正規化
      attributes[:middle_name] = nil if has_middle_name == 0

      # 手動入力モードの場合、町域はnil
      attributes[:home_address_town] = nil if home_is_address_selected_manually == 1
      if employment_status == 1 && workplace_is_address_selected_manually == 1
        attributes[:workplace_address_town] = nil
      end

      # 就労していない場合は勤務先情報をnilに
      if employment_status != 1
        attributes[:workplace_name] = nil
        attributes[:workplace_phone_number] = nil
        attributes[:workplace_is_address_selected_manually] = nil
        attributes[:workplace_postal_code] = nil
        attributes[:workplace_prefecture_code] = nil
        attributes[:workplace_master_city_id] = nil
        attributes[:workplace_address_town] = nil
        attributes[:workplace_address_later] = nil
      end

      attributes
    end

    private

    # 郵便番号の正規化（全角→半角、ハイフン除去）
    #
    # @param postal_code [String] 郵便番号
    # @return [String, nil] 正規化された郵便番号
    def normalize_postal_code(postal_code)
      return nil if postal_code.blank?

      postal_code.to_s.tr('０-９－ー', '0-9--').gsub('-', '')
    end

    # 電話番号の正規化（数字とハイフンを半角に統一、スペース・括弧を削除）
    #
    # @param phone_number [String] 電話番号
    # @return [String, nil] 正規化された電話番号
    def normalize_phone_number(phone_number)
      return nil if phone_number.blank?

      phone_number.to_s
                  .tr('０-９－ー', '0-9--')  # 全角数字・全角ハイフン・長音記号→半角
                  .gsub(/[\s()（）]/, '')    # スペース・括弧を削除
    end

    # メールアドレスの正規化（全角→半角）
    #
    # @param email [String] メールアドレス
    # @return [String, nil] 正規化されたメールアドレス
    def normalize_email(email)
      return nil if email.blank?

      email.to_s.tr('０-９ａ-ｚＡ-Ｚ＠．', '0-9a-zA-Z@.')
    end
  end
end
