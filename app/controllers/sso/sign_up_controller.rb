# frozen_string_literal: true

module Sso
  class SignUpController < ApplicationController
    # GET /sso/sign_up?login_challenge=xxx
    # SSO会員登録画面（エントリポイント）
    def index
      @login_challenge = params[:login_challenge]

      if @login_challenge.blank?
        redirect_to root_path, alert: '不正なアクセスです'
        return
      end

      # 既にログイン済みの場合は自動的にログイン承認
      if current_user
        begin
          response = HydraService.accept_login_request(@login_challenge, current_user.id)
          redirect_to response, allow_other_host: true
        rescue HydraError => e
          Rails.logger.error "Hydra login accept error during signup: #{e.message}"
          redirect_to root_path, alert: 'ログイン処理中にエラーが発生しました'
        end
        return
      end

      # Phase 1-A: 仮のERBページを表示
      # Phase 2: Reactマウントポイントに置き換え
      render :index
    end
  end
end
