# frozen_string_literal: true

module Sso
  module Api
    module SignUp
      class CompleteController < Sso::Api::BaseController
        # POST /sso/api/sign_up/complete
        # 会員登録完了 → User作成 → ログイン → Hydra連携
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

          # login_challengeを先に取得（キャッシュ削除前）
          login_challenge = CacheService.get_signup_cache(token, 'login_challenge')

          # SignupService委譲
          result = SignupService.complete_registration(
            token: token,
            request: request
          )

          unless result.success?
            return render json: {
              errors: { base: [result.error_message] }
            }, status: :unprocessable_content
          end

          # 認証トークン生成・Cookie設定
          auth_token = generate_auth_token(result.user)
          set_auth_cookie(auth_token)

          # レスポンス構築
          response_data = {
            success: true,
            message: '会員登録が完了しました'
          }

          # フロー判定
          flow_type = login_challenge.present? ? 'oauth2' : 'web'
          response_data[:flow_type] = flow_type

          Rails.logger.info "SSO SignUp Complete - login_challenge: #{login_challenge.present? ? 'present' : 'nil'}"
          Rails.logger.info "SSO SignUp Complete - flow_type: #{flow_type}"

          if flow_type == 'oauth2'
            # OAuth2の場合はHydraリダイレクトURL生成
            begin
              hydra_redirect = HydraService.accept_login_request(login_challenge, result.user.id)
              response_data[:hydra_redirect] = hydra_redirect

              Rails.logger.info "SSO SignUp Complete - hydra_redirect: #{hydra_redirect}"

              # 認証ログはConsent処理時に記録される
            rescue HydraError => e
              Rails.logger.warn "Hydra challenge expired during signup: #{e.message}"
              # Hydra challengeが期限切れの場合は通常フローへ
              response_data[:redirect_to] = '/users/profile'
              response_data[:notice] = '登録完了しました。RP側から再度ログインしてください。'
            end
          else
            # 通常の場合はprofileページ（login_challengeなし）
            response_data[:redirect_to] = '/users/profile'

            # 認証ログはConsentがないため、ここでは記録しない
            # （SSO経由でない直接登録はUsers版を使用）
          end

          # レスポンス返却
          Rails.logger.info "SSO SignUp Complete - response_data: #{response_data.inspect}"
          render json: response_data
        rescue StandardError => e
          Rails.logger.error "Sso::Api::SignUp::CompleteController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
