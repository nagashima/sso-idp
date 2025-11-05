# frozen_string_literal: true

module Users
  module Api
    module SignUp
      class ProfileController < Users::Api::BaseController
        # POST /users/api/sign_up/profile
        # プロフィール情報受け取り → Valkeyに保存
        def create
          # パラメータ取得
          token = params[:token]
          profile_params = params.permit(:name, :birth_date, :address)

          validation_errors = {}

          # トークン検証
          if token.blank?
            validation_errors[:token] = ['トークンが必要です']
          end

          # 名前検証（Phase 1-Aでは最小限）
          if profile_params[:name].blank?
            validation_errors[:name] = [I18n.t('activerecord.errors.messages.blank')]
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
          Rails.logger.error "ProfileController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
