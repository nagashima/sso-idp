# frozen_string_literal: true

module Users
  # パスワード入力用のForm Object
  # 会員登録時のパスワード設定で使用
  class PasswordForm < Form
    attr_accessor :password, :password_confirmation, :token

    # パスワード
    validates :password,
              presence: { message: 'パスワードを入力してください' },
              length: { minimum: 8, maximum: 128, message: 'パスワードは8文字以上で入力してください' }

    # スペースのみのパスワードを禁止
    validate :password_not_only_spaces

    # パスワード（確認）
    validates :password_confirmation,
              presence: { message: 'パスワード（確認のため再入力）を入力してください' }

    # パスワード一致チェック
    validates :password,
              confirmation: { message: 'パスワードと再入力パスワードが一致しません' }

    # Strong Parametersからの初期化
    #
    # @param params [ActionController::Parameters] リクエストパラメータ
    # @return [Users::PasswordForm] 初期化されたFormオブジェクト
    def self.initialize_from_params(params)
      return new if params[:password_form].blank?

      permitted = params.require(:password_form).permit(
        :password,
        :password_confirmation,
        :token
      )
      new(permitted)
    end

    private

    # パスワードがスペースのみでないことを検証
    def password_not_only_spaces
      return if password.blank?

      if password.strip.empty?
        errors.add(:password, 'パスワードは8文字以上で入力してください')
      end
    end
  end
end
