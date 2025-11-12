# frozen_string_literal: true

module Users
  module Api
    module SignUp
      class ProfileController < Users::Api::BaseController
        wrap_parameters false

        # POST /users/api/sign_up/profile
        # プロフィール情報受け取り → Valkeyに保存
        def create
          # パラメータ取得
          token = params[:token]
          profile_params = params.permit(
            :last_name, :first_name, :has_middle_name, :middle_name, :last_kana_name, :first_kana_name,
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

          validation_errors = {}

          # トークン検証
          if token.blank?
            validation_errors[:token] = ['トークンが必要です']
          end

          # 必須項目の検証
          if profile_params[:last_name].blank?
            validation_errors[:last_name] = ['姓を入力してください']
          end

          if profile_params[:first_name].blank?
            validation_errors[:first_name] = ['名を入力してください']
          end

          if profile_params[:last_kana_name].blank?
            validation_errors[:last_kana_name] = ['姓（かな）を入力してください']
          elsif !profile_params[:last_kana_name].match?(/\A[ぁ-ん]+\z/)
            validation_errors[:last_kana_name] = ['姓（かな）はひらがなで入力してください']
          end

          if profile_params[:first_kana_name].blank?
            validation_errors[:first_kana_name] = ['名（かな）を入力してください']
          elsif !profile_params[:first_kana_name].match?(/\A[ぁ-ん]+\z/)
            validation_errors[:first_kana_name] = ['名（かな）はひらがなで入力してください']
          end

          if profile_params[:birth_date].blank?
            validation_errors[:birth_date] = ['生年月日を入力してください']
          end

          if profile_params[:gender_code].blank?
            validation_errors[:gender_code] = ['性別を選択してください']
          elsif !%w[1 2 3 4].include?(profile_params[:gender_code])
            validation_errors[:gender_code] = ['性別の選択が不正です']
          end

          if profile_params[:phone_number].blank?
            validation_errors[:phone_number] = ['携帯電話を入力してください']
          end

          # 自動入力モード（is_address_selected_manually = 0）の場合のみ郵便番号必須
          if profile_params[:home_is_address_selected_manually] == '0' && profile_params[:home_postal_code].blank?
            validation_errors[:home_postal_code] = ['郵便番号を入力してください']
          end

          if profile_params[:home_address_later].blank?
            validation_errors[:home_address_later] = ['番地以降を入力してください']
          end

          if profile_params[:employment_status].blank?
            validation_errors[:employment_status] = ['就労状況を選択してください']
          elsif !%w[1 2 3].include?(profile_params[:employment_status])
            validation_errors[:employment_status] = ['就労状況の選択が不正です']
          end

          # 就労=1の場合は勤務先必須
          if profile_params[:employment_status] == '1'
            if profile_params[:workplace_name].blank?
              validation_errors[:workplace_name] = ['勤務先名を入力してください']
            end

            if profile_params[:workplace_phone_number].blank?
              validation_errors[:workplace_phone_number] = ['勤務先電話番号を入力してください']
            end

            # 自動入力モードの場合のみ郵便番号必須
            if profile_params[:workplace_is_address_selected_manually] == '0' && profile_params[:workplace_postal_code].blank?
              validation_errors[:workplace_postal_code] = ['勤務先郵便番号を入力してください']
            end

            if profile_params[:workplace_address_later].blank?
              validation_errors[:workplace_address_later] = ['勤務先番地以降を入力してください']
            end
          end

          # バリデーションエラーがある場合は業務的エラーとして返す
          unless validation_errors.empty?
            return render json: { errors: validation_errors }, status: :unprocessable_content
          end

          # トークン有効性確認
          signup_ticket = SignupTicketService.find_valid_ticket(token)
          unless signup_ticket
            return render json: {
              errors: { token: ['無効なトークンです'] }
            }, status: :unprocessable_content
          end

          # プロフィールをValkeyに保存
          CacheService.save_signup_cache(token, 'profile', profile_params.to_h)

          # レスポンス返却
          render json: {
            success: true,
            message: 'プロフィール情報を保存しました'
          }
        rescue StandardError => e
          Rails.logger.error "Users::Api::SignUp::ProfileController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
