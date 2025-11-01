# frozen_string_literal: true

# HydraClientService: Hydra Admin API連携
# HydraAdminClientをラップし、Serviceレイヤーのインターフェースを提供
class HydraClientService
  # ログイン承認
  #
  # @param challenge [String] login_challenge
  # @param user_id [Integer] ユーザーID
  # @param remember [Boolean] ログイン状態を記憶するか
  # @param remember_for [Integer] 記憶する秒数
  # @return [String] リダイレクト先URL
  # @raise [HydraError] Hydra API呼び出しエラー
  def self.accept_login_request(challenge, user_id, remember: true, remember_for: 3600)
    response = HydraAdminClient.accept_login_request(challenge, user_id.to_s)
    response['redirect_to']
  rescue HydraError => e
    Rails.logger.error "HydraClientService.accept_login_request failed: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "HydraClientService.accept_login_request unexpected error: #{e.message}"
    raise HydraError, e.message
  end

  # 同意承認
  #
  # @param challenge [String] consent_challenge
  # @param user [User] ユーザーオブジェクト
  # @param scopes [Array<String>] 許可するスコープ
  # @return [String] リダイレクト先URL
  # @raise [HydraError] Hydra API呼び出しエラー
  def self.accept_consent_request(challenge, user, scopes)
    id_token_claims = {
      sub: user.id.to_s,
      email: user.email,
      name: user.name
    }

    response = HydraAdminClient.accept_consent_request(challenge, scopes, id_token_claims)
    response['redirect_to']
  rescue HydraError => e
    Rails.logger.error "HydraClientService.accept_consent_request failed: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "HydraClientService.accept_consent_request unexpected error: #{e.message}"
    raise HydraError, e.message
  end
end
