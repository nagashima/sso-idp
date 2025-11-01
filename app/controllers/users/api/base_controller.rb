# frozen_string_literal: true

module Users
  module Api
    class BaseController < ApplicationController
      # CSRF無効化（API用、Cookie認証で運用）
      skip_before_action :verify_authenticity_token

      # JSON解析エラーのキャッチ
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_json_parse_error

      private

      # エラーハンドリング: JSON解析エラー
      def render_json_parse_error
        render json: { error: 'Invalid JSON' }, status: :bad_request
      end

      # エラーハンドリング: 必須パラメータ不足
      def render_missing_param_error(param_name)
        render json: { error: "Missing #{param_name} parameter" }, status: :bad_request
      end

      # JWT実装: 一時トークン生成（2FA用）
      def generate_temp_token(user)
        JWT.encode(
          {
            user_id: user.id,
            exp: 10.minutes.from_now.to_i,
            purpose: 'temp_auth'
          },
          Rails.application.secret_key_base
        )
      end

      # JWT実装: 一時トークン検証
      def verify_temp_token(token)
        payload = JWT.decode(token, Rails.application.secret_key_base).first
        return nil unless payload['purpose'] == 'temp_auth'
        User.find(payload['user_id'])
      rescue JWT::ExpiredSignature
        @token_error = 'Token expired'
        nil
      rescue JWT::DecodeError, JWT::VerificationError
        @token_error = 'Invalid token'
        nil
      rescue ActiveRecord::RecordNotFound
        @token_error = 'Invalid token'
        nil
      end

      # JWT実装: 認証トークン生成（ログイン完了時）
      def generate_auth_token(user)
        JWT.encode(
          {
            user_id: user.id,
            exp: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now.to_i
          },
          Rails.application.secret_key_base
        )
      end

      # Cookie設定: 認証トークン
      def set_auth_cookie(auth_token)
        secure_flag = Rails.env.production? || ENV['HOST_PORT'] == '443'

        cookie_options = {
          value: auth_token,
          expires: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now,
          httponly: true,
          secure: secure_flag,
          same_site: :lax
        }

        cookies[:auth_token] = cookie_options
      end
    end
  end
end
