class Users::ActivationController < ApplicationController
  # メール認証処理
  def activate
    token = params[:token]
    @user = User.find_by(activation_token: token)
    
    if @user && @user.activation_token_valid?(token)
      @user.activate!
      redirect_to users_activated_path
    else
      @error_message = '無効なアクティベーションリンクです'
      render template: 'home/index', status: :not_found
    end
  end

  # 本登録完了画面
  def activated
  end
end