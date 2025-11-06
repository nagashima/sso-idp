# frozen_string_literal: true

# SignupTicketモデルの操作を担当するService
# 会員登録チケットの作成・検証・更新を管理
class SignupTicketService
  # 会員登録チケット作成
  #
  # @param email [String] メールアドレス
  # @param login_challenge [String, nil] SSOフロー用のlogin_challenge（オプション）
  # @return [SignupTicket] 作成されたSignupTicketオブジェクト
  # @raise [ActiveRecord::RecordInvalid] バリデーションエラー時
  def self.create_ticket(email:, login_challenge: nil)
    SignupTicket.create!(
      email: email,
      token: SignupTicket.generate_token,
      expires_at: 24.hours.from_now,
      login_challenge: login_challenge
    )
  end

  # 有効なチケットを検索
  # メール確認済み かつ 有効期限内のチケットのみ返す
  #
  # @param token [String] チケットトークン
  # @return [SignupTicket, nil] 有効なチケット、または nil
  def self.find_valid_ticket(token)
    ticket = SignupTicket.find_by(token: token)
    return nil unless ticket
    return nil if ticket.expired?
    return nil unless ticket.confirmed?
    ticket
  end

  # メール確認済みマーク
  # メールリンククリック時に呼び出される
  #
  # @param token [String] チケットトークン
  # @return [Boolean] 成功時 true、失敗時 false
  def self.mark_as_confirmed(token)
    ticket = SignupTicket.find_by(token: token)
    return false unless ticket
    return false if ticket.expired?

    ticket.update!(confirmed_at: Time.current)
    true
  end

  # 使用済みマーク（削除）
  # 登録完了時に呼び出される
  #
  # @param signup_ticket [SignupTicket] 削除するチケットオブジェクト
  # @return [Boolean] 削除成功時 true
  def self.mark_as_used(signup_ticket)
    signup_ticket.destroy
  end

  # チケット検索（有効性チェックなし）
  # テストやデバッグ用
  #
  # @param token [String] チケットトークン
  # @return [SignupTicket, nil] チケットオブジェクト、または nil
  def self.find_by_token(token)
    SignupTicket.find_by(token: token)
  end
end
