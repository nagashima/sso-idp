# frozen_string_literal: true

module Sso
  module Api
    module SignUp
      class PasswordController < Sso::Api::BaseController
        # POST /sso/api/sign_up/password
        # パスワード受け取り → Valkeyに保存
        def create
          # Form Objectの初期化
          form = Users::PasswordForm.new(
            password: params[:password],
            password_confirmation: params[:password_confirmation],
            token: params[:token]
          )

          # バリデーション
          unless form.valid?
            return render json: { errors: form.errors.messages }, status: :unprocessable_content
          end

          # トークン検証
          if form.token.blank?
            return render json: {
              errors: { token: ['トークンが必要です'] }
            }, status: :unprocessable_content
          end

          # トークン有効性確認
          signup_ticket = SignupTicketService.find_valid_ticket(form.token)
          unless signup_ticket
            return render json: {
              errors: { token: ['無効なトークンです'] }
            }, status: :unprocessable_content
          end

          # パスワードをValkeyに保存
          CacheService.save_signup_cache(form.token, 'password', form.password)

          # レスポンス返却
          render json: {
            success: true,
            message: 'パスワードを保存しました'
          }
        rescue StandardError => e
          Rails.logger.error "Sso::Api::SignUp::PasswordController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
