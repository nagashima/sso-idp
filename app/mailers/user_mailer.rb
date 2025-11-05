class UserMailer < ApplicationMailer
  default from: 'noreply@sso-idp.local'

  def activation_email(user)
    @user = user
    @activation_url = users_activate_url(token: user.activation_token)
    
    mail(
      to: @user.email,
      subject: '【SSO IdP】メール認証のお願い'
    )
  end

  def auth_code_email(user)
    @user = user
    @auth_code = user.auth_code

    mail(
      to: @user.email,
      subject: '【SSO IdP】ログイン認証コード'
    )
  end

  def signup_confirmation_email(signup_ticket)
    @signup_ticket = signup_ticket
    # 共通エンドポイント（フロー判定はverify_email側で行う）
    @confirmation_url = verify_email_url(token: signup_ticket.token)

    mail(
      to: @signup_ticket.email,
      subject: '【SSO IdP】会員登録メールアドレス確認'
    )
  end
end