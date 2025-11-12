# frozen_string_literal: true

module Users
  module Api
    module SignUp
      class CompleteController < Users::Api::BaseController
        # POST /users/api/sign_up/complete
        # 会員登録完了 → User作成 → ログイン
        def create
          # パラメータ取得
          token = params[:token]

          validation_errors = {}

          # トークン検証
          if token.blank?
            validation_errors[:token] = ['トークンが必要です']
          end

          # バリデーションエラーがある場合は業務的エラーとして返す
          unless validation_errors.empty?
            return render json: { errors: validation_errors }, status: :unprocessable_content
          end

          # SignupService委譲
          result = SignupService.complete_registration(
            token: token,
            request: request
          )

          if result.success?
            # 認証トークン生成・Cookie設定
            auth_token = generate_auth_token(result.user)
            set_auth_cookie(auth_token)

            # レスポンス返却
            render json: {
              success: true,
              message: '会員登録が完了しました',
              redirect_to: '/users/profile'
            }
          else
            render json: {
              errors: { base: [result.error_message] }
            }, status: :unprocessable_content
          end
        rescue StandardError => e
          Rails.logger.error "CompleteController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
