# frozen_string_literal: true

module Users
  module Api
    module SignUp
      class EmailController < Users::Api::BaseController
        # POST /users/api/sign_up/email
        # メールアドレス送信 → SignupTicket作成 → 確認メール送信
        def create
          # パラメータ取得
          email = params[:email]

          validation_errors = {}

          # メールアドレス検証
          if email.blank?
            validation_errors[:email] = [I18n.t('activerecord.errors.messages.blank')]
          elsif !(email =~ URI::MailTo::EMAIL_REGEXP)
            validation_errors[:email] = [I18n.t('activerecord.errors.messages.invalid')]
          else
            # 重複チェック
            if User.exists?(email: email)
              validation_errors[:email] = ['このメールアドレスは既に登録されています']
            end
          end

          # バリデーションエラーがある場合は業務的エラーとして返す
          unless validation_errors.empty?
            return render json: { errors: validation_errors }, status: :unprocessable_content
          end

          # SignupTicket作成
          signup_ticket = SignupTicketService.create_ticket(
            email: email,
            login_challenge: params[:login_challenge]
          )

          # login_challengeがあればキャッシュに保存
          if params[:login_challenge].present?
            CacheService.save_signup_cache(
              signup_ticket.token,
              'login_challenge',
              params[:login_challenge]
            )
          end

          # 確認メール送信
          UserMailer.signup_confirmation_email(signup_ticket).deliver_now

          # レスポンス返却
          render json: {
            success: true,
            token: signup_ticket.token,
            message: '確認メールを送信しました。メールをご確認ください。',
            expires_at: signup_ticket.expires_at.iso8601
          }
        rescue ActiveRecord::RecordInvalid => e
          render json: {
            errors: { base: [e.message] }
          }, status: :unprocessable_content
        rescue StandardError => e
          Rails.logger.error "EmailController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
