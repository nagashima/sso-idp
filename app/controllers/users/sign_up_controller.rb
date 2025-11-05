# frozen_string_literal: true

module Users
  class SignUpController < ApplicationController
    # 既ログイン時はリダイレクト
    before_action :redirect_if_logged_in

    # GET /users/sign_up
    # 会員登録画面（エントリポイント）
    def index
      # Phase 1-A: 仮のERBページを表示
      # Phase 2: Reactマウントポイントに置き換え
      render :index
    end

    private

    def redirect_if_logged_in
      if current_user
        redirect_to root_path, alert: '既にログインしています。'
      end
    end
  end
end
