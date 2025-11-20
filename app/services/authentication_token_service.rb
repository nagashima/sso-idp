# frozen_string_literal: true

# 認証トークン生成サービス
#
# JWT認証トークンの生成とCookie設定オプションを提供
# Users::Api::BaseControllerとSso::Api::BaseControllerで共通利用
class AuthenticationTokenService
  # 一時トークン生成（メール認証用、10分有効）
  #
  # @param user [User] ユーザーオブジェクト
  # @return [String] JWTトークン
  def self.generate_temp_token(user)
    JWT.encode(
      {
        user_id: user.id,
        exp: 10.minutes.from_now.to_i,
        purpose: 'temp_auth'
      },
      Rails.application.secret_key_base
    )
  end

  # 認証トークン生成（ログイン用、設定された有効期限）
  #
  # @param user [User] ユーザーオブジェクト
  # @return [String] JWTトークン
  def self.generate_auth_token(user)
    JWT.encode(
      {
        user_id: user.id,
        exp: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now.to_i
      },
      Rails.application.secret_key_base
    )
  end

  # Cookie設定オプション生成
  #
  # nginx経由（X-Forwarded-Proto: https）または直接HTTPS接続の場合にsecureフラグを立てる
  #
  # @param auth_token [String] 認証トークン
  # @param request [ActionDispatch::Request] リクエストオブジェクト
  # @return [Hash] Cookie設定オプション
  def self.auth_cookie_options(auth_token, request)
    secure_flag = request.ssl? || request.headers['X-Forwarded-Proto'] == 'https'

    {
      value: auth_token,
      expires: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now,
      httponly: true,
      secure: secure_flag,
      same_site: :lax
    }
  end
end
