# frozen_string_literal: true

class Users::SignOutController < ApplicationController
  # CSRF検証をスキップ（セッション切れ時のエラー回避）
  skip_forgery_protection only: [:destroy]

  # DELETE /users/sign_out - ローカルログアウト（通常WEB用）
  def destroy
    if current_user
      # IdPローカルセッションをクリア
      perform_local_logout

      redirect_to root_path, notice: 'ログアウトしました'
    else
      redirect_to root_path, notice: '既にログアウトしています'
    end
  end

  private

  # ローカルログアウト処理
  def perform_local_logout
    # 認証ログ: ログアウト
    AuthenticationLoggerService.log_logout(current_user, request, logout_type: 'local')

    cookies.signed[:auth_token] = nil
    session.clear
    Rails.logger.info "IdP local logout completed at #{Time.current}"
  end
end
