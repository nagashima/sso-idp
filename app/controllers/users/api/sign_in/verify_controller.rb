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

          # 認証コード検証
          unless user.mail_authentication_code_valid?(auth_code)
            # 認証コード期限切れの場合は専用エラー
            if user.mail_authentication_code.present? && user.mail_authentication_expires_at&.past?
              return render_token_expired_error
            end
            return render_verification_error
          end

          # ログイン完了処理
          user.update_last_sign_in!
          user.clear_mail_authentication_code!

          # 認証トークン生成・Cookie設定
          auth_token = generate_auth_token(user)
          set_auth_cookie(auth_token)

          # 認証ログ: ログイン成功
          AuthenticationLoggerService.log_login_success(
            user,
            request,
            login_method: 'normal',
            redirect_to: '/users/profile'
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
        end

        private

        # エラーハンドリング
        def render_token_error
          error_message = @token_error || 'Invalid token'
          render json: { error: error_message }, status: :bad_request
        end

        def render_token_expired_error
          render json: { error: 'Token expired' }, status: :bad_request
        end

        def render_verification_error
          render json: { error: 'Invalid verification code' }, status: :bad_request
        end
      end
    end
  end
end
