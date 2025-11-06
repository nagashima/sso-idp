# frozen_string_literal: true

# SignupService: 会員登録フロー統括
# 複数のServiceを横断して登録処理を実行
class SignupService
  # Result Object パターン
  class Result
    attr_reader :user, :error_message

    def initialize(success:, user: nil, error_message: nil)
      @success = success
      @user = user
      @error_message = error_message
    end

    def success?
      @success
    end
  end

  # 会員登録完了処理
  #
  # @param token [String] SignupTicketのトークン
  # @param request [ActionDispatch::Request] HTTPリクエストオブジェクト
  # @return [Result] 処理結果
  def self.complete_registration(token:, request:)
    # 1. トークン検証
    signup_ticket = SignupTicketService.find_valid_ticket(token)
    return Result.new(success: false, error_message: '無効なトークンです') if signup_ticket.nil?

    # 2. キャッシュデータ取得
    cached_data = CacheService.get_signup_data(token)
    return Result.new(success: false, error_message: 'データが見つかりません') if cached_data.nil?

    # 3. User作成
    user = UserService.create_from_signup(
      email: signup_ticket.email,
      password: cached_data[:password],
      profile: cached_data[:profile]
    )

    return Result.new(success: false, error_message: 'ユーザー作成に失敗しました') if user.nil?

    # 4. クリーンアップ
    CacheService.delete_signup_cache(token)
    SignupTicketService.mark_as_used(signup_ticket)

    # 5. ログ記録
    AuthenticationLoggerService.log_user_registration(user, request)

    Result.new(success: true, user: user)
  rescue StandardError => e
    Rails.logger.error "SignupService.complete_registration failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    Result.new(success: false, error_message: 'システムエラーが発生しました')
  end
end
