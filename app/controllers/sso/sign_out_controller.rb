class Sso::SignOutController < ApplicationController
  # GET /sso/sign_out?logout_challenge=... - Hydraからのログアウト要求
  def logout
    logout_challenge = params[:logout_challenge]

    if logout_challenge.blank?
      redirect_to root_path, alert: '不正なアクセスです'
      return
    end

    begin
      # Hydraからのログアウト要求詳細を取得
      logout_request = HydraClient.get_logout_request(logout_challenge)

      # IdPローカルセッションをクリア
      perform_local_logout

      # Hydraのログアウト要求を受け入れ
      response = HydraClient.accept_logout_request(logout_challenge)

      # Hydraが指定したリダイレクト先に転送（通常はRPのトップページ）
      redirect_to response['redirect_to'], allow_other_host: true

    rescue HydraError => e
      Rails.logger.error "Failed to handle logout request: #{e.message}"
      # エラー時もローカルログアウトは実行
      perform_local_logout
      redirect_to root_path, notice: 'ログアウトしました'
    end
  end

  private

  def perform_local_logout
    cookies.signed[:auth_token] = nil
    session.clear
    Rails.logger.info "IdP local logout completed at #{Time.current}"
  end
end