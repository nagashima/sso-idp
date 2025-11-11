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

          # 認証コード検証
          unless user.auth_code_valid?(auth_code)
            # 認証コード期限切れの場合は専用エラー
            if user.auth_code.present? && user.auth_code_expires_at&.past?
              return render_token_expired_error
            end
            return render_verification_error
          end

          # ログイン完了処理
          user.update_last_login!
          user.clear_auth_code!

          # 認証トークン生成・Cookie設定
          auth_token = generate_auth_token(user)
          set_auth_cookie(auth_token)

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
              # ★初回RPログイン記録★
              login_request = HydraClient.get_login_request(login_challenge)
              client_id = login_request.dig('client', 'client_id')
              relying_party = RelyingParty.find_by(api_key: client_id)
              record_first_rp_login(user, relying_party) if relying_party

              hydra_redirect = HydraService.accept_login_request(login_challenge, user.id)
              response_data[:hydra_redirect] = hydra_redirect

              # 認証ログ: OAuth2ログイン成功
              AuthenticationLoggerService.log_login_success(
                user,
                request,
                login_method: 'oauth2',
                redirect_to: 'hydra_redirect'
              )
            rescue HydraError => e
              Rails.logger.error "Hydra login accept error: #{e.message}"
              return render json: { error: 'OAuth2 processing failed' }, status: :internal_server_error
            end
          else
            # 通常の場合はprofileページ
            response_data[:redirect_to] = '/profile'

            # 認証ログ: 通常ログイン成功
            AuthenticationLoggerService.log_login_success(
              user,
              request,
              login_method: 'normal',
              redirect_to: '/profile'
            )
          end

          # レスポンス返却
          render json: response_data
        end

        private

        # 初回RPログイン記録
        def record_first_rp_login(user, relying_party)
          unless user.relying_parties.include?(relying_party)
            user.relying_parties << relying_party
            Rails.logger.info "First RP login: user_id=#{user.id}, rp=#{relying_party.name} (#{relying_party.domain})"
          end
        end

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
