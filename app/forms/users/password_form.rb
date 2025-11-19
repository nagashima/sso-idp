# frozen_string_literal: true

module Users
  # パスワード入力用のForm Object
  # 会員登録時のパスワード設定で使用
  class PasswordForm < Form
    include ValidatableUserPassword

    attr_accessor :token

    # Strong Parametersからの初期化（WEB専用）
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
  end
end
