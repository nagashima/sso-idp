# frozen_string_literal: true

module Users
  module Api
    module SignIn
      class AuthenticateController < Users::Api::BaseController
        # POST /users/api/sign_in/authenticate
        # メール・パスワード認証 → temp_token発行 → 2FAメール送信
        def create
          # 技術的エラー：完全にパラメータキーが存在しない場合
          if !params.key?(:email) && !params.key?(:password)
            return render_missing_param_error('email')
          end

          # パラメータ取得
          email = params[:email]
          password = params[:password]

          validation_errors = {}

          # メールアドレス検証
          if email.blank?
            validation_errors[:email] = [I18n.t('activerecord.errors.messages.blank')]
          elsif !(email =~ URI::MailTo::EMAIL_REGEXP)
            validation_errors[:email] = [I18n.t('activerecord.errors.messages.invalid')]
          end

          # パスワード検証
          if password.blank?
            validation_errors[:password] = [I18n.t('activerecord.errors.messages.blank')]
          end

          # バリデーションエラーがある場合は業務的エラーとして返す
          unless validation_errors.empty?
            return render json: { errors: validation_errors }, status: :unprocessable_content
          end

          # ユーザー認証
          user = authenticate_user_for_login(email, password)
          return render_authentication_error unless user

          # アクティベーション確認
          return render_activation_error unless user.activated?

          # 2段階認証コード生成・保存
          user.generate_mail_authentication_code!

          # 認証メール送信（即座に - テスト環境対応）
          UserMailer.auth_code_email(user).deliver_now

          # 一時トークン生成
          temp_token = generate_temp_token(user)

          # 認証ログ: ログイン開始（通常WEB）
          # Note: OAuth2専用メソッドだが、通常WEBでも使用（client_idはnilでOK）
          AuthenticationLoggerService.log_oauth2_login_start(
            request,
            client_id: nil,
            login_challenge: nil
          )

          # レスポンス構築
          response_data = {
            temp_token: temp_token,
            status: 'awaiting_2fa',
            message: I18n.t('api.auth.code_sent'),
            flow_type: 'web',
            expires_at: 10.minutes.from_now.iso8601
          }

          # 開発環境のみ：認証コードを表示（デバッグ用）
          if Rails.env.development?
            response_data[:debug_auth_code] = user.mail_authentication_code
          end

          # レスポンス返却
          render json: response_data
        end

        private

        # 認証・バリデーション
        def authenticate_user_for_login(email, password)
          # ユーザー検索・認証
          user = User.find_by(email: email)
          return nil unless user&.authenticate(password)
          user
        end

        # エラーハンドリング
        def render_authentication_error
          # 認証失敗は業務的エラー
          render json: {
            errors: {
              base: [I18n.t('api.auth.invalid_credentials')]
            }
          }, status: :unprocessable_content
        end

        def render_activation_error
          render json: {
            errors: {
              base: [I18n.t('api.auth.user_not_activated')]
            }
          }, status: :unprocessable_content
        end
      end
    end
  end
end
