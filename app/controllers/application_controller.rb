class ApplicationController < ActionController::Base

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # CSRF保護強化
  protect_from_forgery with: :exception, prepend: true

  # セッション期限切れ時のCSRFエラーをハンドリング
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_session_expired

  # セキュリティヘッダー設定
  before_action :set_security_headers

  # ビューでも使えるようにヘルパーメソッドとして登録
  helper_method :current_user, :logged_in?

  # JWT認証ヘルパー
  def current_user
    return @current_user if defined?(@current_user)

    token = cookies[:auth_token]
    return @current_user = nil unless token

    begin
      payload = JWT.decode(token, Rails.application.secret_key_base).first
      @current_user = User.find(payload['user_id'])
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      @current_user = nil
    end
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    redirect_to root_path, alert: 'ログインが必要です。' unless logged_in?
  end

  def verify_user_ownership
    unless current_user == @user
      redirect_to root_path, alert: '他のユーザーの情報にはアクセスできません。'
    end
  end

  private

  # セッション期限切れ時の処理
  def handle_session_expired
    Rails.logger.warn "Session expired - CSRF token invalid. Clearing session and redirecting to login."
    cookies.delete(:auth_token)
    reset_session
    redirect_to login_path, alert: 'セッションの有効期限が切れました。再度ログインしてください。'
  end

  def set_security_headers
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'

    # Vite開発サーバー用WebSocket接続許可（開発環境のみ）
    csp_policy = "default-src 'self'; script-src 'self' 'unsafe-inline' cdn.tailwindcss.com; style-src 'self' 'unsafe-inline' cdn.tailwindcss.com"
    if Rails.env.development?
      vite_host = ENV['VITE_HMR_HOST'] || 'localhost'
      vite_port = ENV['VITE_RUBY_PORT'] || '3036'
      csp_policy += "; connect-src 'self' wss://#{vite_host} wss://#{vite_host}:#{vite_port} ws://localhost:#{vite_port} ws://localhost:3037"
    end

    response.headers['Content-Security-Policy'] = csp_policy
  end
end
