# frozen_string_literal: true

module Users
  module Api
    module SignIn
      class VerifyController < Users::Api::BaseController
        # POST /users/api/sign_in/verify
        # temp_token + 認証コード検証 → ログイン完了
        def create
          # パラメータ必須チェック（技術的エラー）
          return render_missing_param_error('temp_token') if params[:temp_token].blank?
          return render_missing_param_error('auth_code') if params[:auth_code].blank?

          temp_token = params[:temp_token]
          auth_code = params[:auth_code]

          # temp_token検証・デコード
          user = verify_temp_token(temp_token)
          return render_token_error unless user

          # UserSignInService委譲
          result = UserSignInService.verify_and_complete(user: user, auth_code: auth_code)

          if result.success?
            # 認証トークン生成・Cookie設定
            auth_token = generate_auth_token(result.user)
            set_auth_cookie(auth_token)

            # 認証ログ: WEBログイン成功
            AuthenticationLoggerService.log_sign_in_success(
              user: result.user,
              request: request,
              sign_in_type: :web
            )

            # レスポンス構築
            response_data = {
              auth_token: auth_token,
              status: 'authenticated',
              message: I18n.t('api.auth.login_success'),
              flow_type: 'web',
              redirect_to: '/users/profile'
            }

            # レスポンス返却
            render json: response_data
          else
            # 失敗ログ記録
            AuthenticationLoggerService.log_sign_in_failure(
              identifier: user.email,
              request: request,
              sign_in_type: :web,
              failure_reason: result.error_reason,
              user: result.user
            )

            # 認証コード期限切れの場合は専用エラー
            if user.mail_authentication_code.present? && user.mail_authentication_expires_at&.past?
              return render_token_expired_error
            end
            render_verification_error
          end
        end

        private

        # エラーハンドリング
        def render_token_error
          error_message = @token_error || I18n.t('api.auth.invalid_token')
          render json: { error: error_message }, status: :bad_request
        end

        def render_token_expired_error
          render json: { error: I18n.t('api.auth.token_expired') }, status: :bad_request
        end

        def render_verification_error
          render json: { error: I18n.t('api.auth.invalid_verification_code') }, status: :bad_request
        end
      end
    end
  end
end
