class AuthenticationLoggerService
  class << self
    # ログイン成功ログ記録
    #
    # @param user [User] ユーザーオブジェクト
    # @param request [ActionDispatch::Request] リクエストオブジェクト
    # @param sign_in_type [Symbol] :web または :sso
    # @param relying_party [RelyingParty, nil] RP（SSOの場合のみ）
    def log_sign_in_success(user:, request:, sign_in_type:, relying_party: nil)
      AuthenticationLog.create!(
        user: user,
        relying_party: relying_party,
        sign_in_type: AuthenticationLog::SIGN_IN_TYPES[sign_in_type],
        ip_address: extract_ip_address(request),
        user_agent: request.user_agent,
        success: true,
        failure_reason: nil,
        identifier: user.email,
        occurred_at: Time.current
      )

      Rails.logger.info({
        event: 'sign_in_success',
        user_id: user.id,
        email: user.email,
        sign_in_type: sign_in_type,
        relying_party_id: relying_party&.id,
        ip_address: extract_ip_address(request),
        timestamp: Time.current.iso8601
      }.to_json)
    end

    # ログイン失敗ログ記録
    #
    # @param identifier [String] メールアドレス等の識別子
    # @param request [ActionDispatch::Request] リクエストオブジェクト
    # @param sign_in_type [Symbol] :web または :sso
    # @param failure_reason [Symbol] 失敗理由（:password_mismatch等）
    # @param user [User, nil] ユーザーオブジェクト（存在する場合）
    # @param relying_party [RelyingParty, nil] RP（SSOの場合のみ）
    def log_sign_in_failure(identifier:, request:, sign_in_type:, failure_reason:, user: nil, relying_party: nil)
      # 環境変数で失敗ログ記録を制御
      return unless ENV.fetch('LOG_FAILED_SIGN_IN', 'true') == 'true'

      AuthenticationLog.create!(
        user: user,
        relying_party: relying_party,
        sign_in_type: AuthenticationLog::SIGN_IN_TYPES[sign_in_type],
        ip_address: extract_ip_address(request),
        user_agent: request.user_agent,
        success: false,
        failure_reason: AuthenticationLog::FAILURE_REASONS[failure_reason],
        identifier: identifier,
        occurred_at: Time.current
      )

      Rails.logger.warn({
        event: 'sign_in_failure',
        user_id: user&.id,
        identifier: identifier,
        sign_in_type: sign_in_type,
        failure_reason: failure_reason,
        relying_party_id: relying_party&.id,
        ip_address: extract_ip_address(request),
        timestamp: Time.current.iso8601
      }.to_json)
    end

    private

    def extract_ip_address(request)
      # プロキシ経由の場合を考慮してIPアドレスを取得
      request.headers['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip ||
        request.headers['HTTP_X_REAL_IP'] ||
        request.remote_ip ||
        request.ip
    end
  end
end
