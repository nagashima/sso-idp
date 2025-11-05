# frozen_string_literal: true

class VerifyEmailController < ApplicationController
  # GET /verify_email/:token
  # メールアドレス確認（共通エンドポイント）
  # トークンからフロー判定してリダイレクト
  def verify
    token = params[:token]

    # SignupTicket検索
    signup_ticket = SignupTicket.find_by(token: token)

    unless signup_ticket
      redirect_to root_path, alert: '無効なトークンです'
      return
    end

    # 期限切れチェック
    if signup_ticket.expires_at < Time.current
      redirect_to root_path, alert: 'トークンの有効期限が切れています'
      return
    end

    # confirmed_at設定
    unless SignupTicketService.mark_as_confirmed(token)
      redirect_to root_path, alert: 'トークンの確認に失敗しました'
      return
    end

    # login_challengeの有無でフロー判定してリダイレクト
    if signup_ticket.login_challenge.present?
      # SSOフロー: login_challengeを渡す
      redirect_to sso_sign_up_path(
        login_challenge: signup_ticket.login_challenge,
        token: token
      )
    else
      # 通常フロー
      redirect_to users_sign_up_path(token: token)
    end
  end
end
