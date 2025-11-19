# frozen_string_literal: true

module Sso
  module Api
    module SignIn
      class VerifyController < Sso::Api::BaseController
        # POST /sso/api/sign_in/verify
        # temp_token + 認証コード検証 → ログイン完了（SSO版、Hydra連携）
        def create
          # パラメータ必須チェック（技術的エラー）
          return render_missing_param_error('temp_token') if params[:temp_token].blank?
          return render_missing_param_error('auth_code') if params[:auth_code].blank?

          temp_token = params[:temp_token]
          auth_code = params[:auth_code]
          login_challenge = params[:login_challenge] # OAuth2パラメータ

          # temp_token検証・デコード
          user = verify_temp_token(temp_token)
          return render_token_error unless user

          # UserSignInService委譲
          result = UserSignInService.verify_and_complete(user: user, auth_code: auth_code)

          if result.success?
            # 認証トークン生成・Cookie設定
            auth_token = generate_auth_token(result.user)
            set_auth_cookie(auth_token)

            # 認証ログ: SSOログイン成功
            AuthenticationLoggerService.log_sign_in_success(
              user: result.user,
              request: request,
              sign_in_type: :sso
            )

            # OAuth2フロー判定
            flow_type = login_challenge.present? ? 'oauth2' : 'web'

            # レスポンス構築
            response_data = {
              auth_token: auth_token,
              status: 'authenticated',
              message: I18n.t('api.auth.login_success'),
              flow_type: flow_type
            }

            # フロー別リダイレクト先設定
            if flow_type == 'oauth2'
              # OAuth2の場合はHydraリダイレクトURL生成
              begin
                hydra_redirect = HydraService.accept_login_request(login_challenge, result.user.id)
                response_data[:hydra_redirect] = hydra_redirect
              rescue HydraError => e
                Rails.logger.error "Hydra login accept error: #{e.message}"
                return render json: { error: 'OAuth2 processing failed' }, status: :internal_server_error
              end
            else
              # 通常の場合はprofileページ
              response_data[:redirect_to] = '/users/profile'
            end

            # レスポンス返却
            render json: response_data
          else
            # 失敗ログ記録
            AuthenticationLoggerService.log_sign_in_failure(
              identifier: user.email,
              request: request,
              sign_in_type: :sso,
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
