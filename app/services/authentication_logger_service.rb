class AuthenticationLoggerService
  class << self
    # 会員登録ログ記録（JSON形式）
    def log_user_registration(user, request, login_method: 'normal')
      Rails.logger.info({
        event: 'user_registration',
        user_id: user.id,
        email: user.email,
        login_method: login_method,
        ip_address: extract_ip_address(request),
        user_agent: request.user_agent,
        timestamp: Time.current.iso8601
      }.to_json)
    end

    # ログインログ記録（JSON形式）
    def log_login(user, request, login_method: 'normal')
      Rails.logger.info({
        event: 'user_login',
        user_id: user.id,
        email: user.email,
        login_method: login_method,
        ip_address: extract_ip_address(request),
        user_agent: request.user_agent,
        timestamp: Time.current.iso8601
      }.to_json)
    end

    # OAuth2ログイン開始
    def log_oauth2_login_start(request, client_id: nil, login_challenge: nil)
      create_log(
        user: nil,
        event_type: AuthenticationLog::EVENT_TYPES[:oauth2_login_start],
        request: request,
        success: true,
        details: {
          client_id: client_id,
          login_challenge: login_challenge
        }
      )
    end

    # パスワード認証
    def log_password_authentication(user_or_email, request, success:, failure_reason: nil)
      user = user_or_email.is_a?(User) ? user_or_email : nil
      email = user_or_email.is_a?(String) ? user_or_email : user&.email

      details = { email: email }
      details[:failure_reason] = failure_reason if failure_reason

      create_log(
        user: user,
        event_type: AuthenticationLog::EVENT_TYPES[:password_authentication],
        request: request,
        success: success,
        details: details
      )
    end

    # 2段階認証
    def log_two_factor_authentication(user, request, success:, failure_reason: nil, code_attempts: 1)
      details = { 
        email: user.email,
        code_attempts: code_attempts
      }
      details[:failure_reason] = failure_reason if failure_reason

      create_log(
        user: user,
        event_type: AuthenticationLog::EVENT_TYPES[:two_factor_authentication],
        request: request,
        success: success,
        details: details
      )
    end

    # ログイン成功
    def log_login_success(user, request, login_method: 'standard', redirect_to: nil)
      create_log(
        user: user,
        event_type: AuthenticationLog::EVENT_TYPES[:login_success],
        request: request,
        success: true,
        details: {
          login_method: login_method,
          redirect_to: redirect_to
        }
      )
    end

    # OAuth2同意
    def log_oauth2_consent(user, request, client_id: nil, scopes: [], consent_challenge: nil)
      create_log(
        user: user,
        event_type: AuthenticationLog::EVENT_TYPES[:oauth2_consent],
        request: request,
        success: true,
        details: {
          client_id: client_id,
          scopes: scopes,
          consent_challenge: consent_challenge
        }
      )
    end

    # ログアウト
    def log_logout(user, request, logout_type: 'standard')
      create_log(
        user: user,
        event_type: AuthenticationLog::EVENT_TYPES[:logout],
        request: request,
        success: true,
        details: {
          logout_type: logout_type
        }
      )
    end

    private

    def create_log(user:, event_type:, request:, success:, details: {})
      AuthenticationLog.create!(
        user: user,
        event_type: event_type,
        ip_address: extract_ip_address(request),
        user_agent: request.user_agent,
        success: success,
        occurred_at: Time.current,
        details: details.compact
      )
    end

    def extract_ip_address(request)
      # プロキシ経由の場合を考慮してIPアドレスを取得
      request.headers['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip ||
        request.headers['HTTP_X_REAL_IP'] ||
        request.remote_ip ||
        request.ip
    end
  end
end