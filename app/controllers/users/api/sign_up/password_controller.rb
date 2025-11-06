# frozen_string_literal: true

module Users
  module Api
    module SignUp
      class PasswordController < Users::Api::BaseController
        # POST /users/api/sign_up/password
        # パスワード受け取り → Valkeyに保存
        def create
          # パラメータ取得
          token = params[:token]
          password = params[:password]

          validation_errors = {}

          # トークン検証
          if token.blank?
            validation_errors[:token] = ['トークンが必要です']
          end

          # パスワード検証
          if password.blank?
            validation_errors[:password] = [I18n.t('activerecord.errors.messages.blank')]
          elsif password.length < 8
            validation_errors[:password] = ['パスワードは8文字以上で入力してください']
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

          # パスワードをValkeyに保存
          CacheService.save_signup_cache(token, 'password', password)

          # レスポンス返却
          render json: {
            success: true,
            message: 'パスワードを保存しました'
          }
        rescue StandardError => e
          Rails.logger.error "PasswordController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
