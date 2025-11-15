# frozen_string_literal: true

module Sso
  module Api
    module SignUp
      class ProfileController < Sso::Api::BaseController
        # POST /sso/api/sign_up/profile
        # プロフィール情報受け取り → Valkeyに保存
        def create
          token = params[:token]

          # トークン検証
          if token.blank?
            return render json: {
              errors: { token: ['トークンが必要です'] }
            }, status: :unprocessable_content
          end

          # SSO版は古いフォームなので、ミドルネーム関連のデフォルト値を設定
          params[:has_middle_name] = 0 unless params[:has_middle_name].present?
          params[:middle_name] = nil unless params[:middle_name].present?

          # Form Objectの初期化とバリデーション
          form = Users::ProfileForm.initialize_from_params(params)

          if form.invalid?
            return render json: {
              errors: form.errors.messages
            }, status: :unprocessable_content
          end

          # トークン有効性確認
          signup_ticket = SignupTicketService.find_valid_ticket(token)
          unless signup_ticket
            return render json: {
              errors: { token: ['無効なトークンです'] }
            }, status: :unprocessable_content
          end

          # プロフィールをValkeyに保存（正規化された値）
          CacheService.save_signup_cache(token, 'profile', form.to_user_attributes)

          # レスポンス返却
          render json: {
            success: true,
            message: 'プロフィール情報を保存しました'
          }
        rescue StandardError => e
          Rails.logger.error "Sso::Api::SignUp::ProfileController.create failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            errors: { base: ['システムエラーが発生しました'] }
          }, status: :internal_server_error
        end
      end
    end
  end
end
