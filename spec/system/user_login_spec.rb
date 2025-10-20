require 'rails_helper'

RSpec.describe "User Login", type: :system do
  before(:each) do
    # ActionMailerの配信をテスト用に設定
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear
  end
  
  describe "正常なログインフロー" do
    it "メールアドレスとパスワードによる2段階認証が成功する" do
      # テスト用アクティベート済みユーザーを作成
      user = create(:user, :activated, 
        email: 'login_test@example.com', 
        password: 'password123',
        password_confirmation: 'password123',
        name: '山田太郎'
      )
      
      # 1. ログイン画面にアクセス
      visit login_path
      expect(page).to have_content 'ログイン'
      
      # 2. 第1段階認証（メール・パスワード）
      fill_in 'email', with: 'login_test@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      # 3. 認証コード入力画面に遷移
      expect(page).to have_current_path(login_verify_path)
      expect(page).to have_selector('[data-testid="auth-code-sent-message"]')  # "〜に認証コードを送信しました"
      expect(page).to have_content '認証コード入力'  # ページタイトル
      
      # 4. メール送信確認
      expect(ActionMailer::Base.deliveries.count).to eq(1)
      sent_email = ActionMailer::Base.deliveries.last
      expect(sent_email.to).to include('login_test@example.com')
      expect(sent_email.subject).to include('認証コード')
      
      # 5. 認証コードを取得して入力
      user.reload
      auth_code = user.auth_code
      expect(auth_code).to be_present
      
      fill_in 'auth_code', with: auth_code
      find('[data-testid="auth-code-submit"]').click
      
      # 6. ログイン成功確認（状態変化で判定）
      expect(page).to have_current_path(root_path)
      expect(page).to have_selector('[data-testid="logged-in-user-info"]')  # ログイン状態の表示
      expect(page).to have_selector('[data-testid="logout-button"]')  # ログアウトボタンが表示
      expect(page).not_to have_link('ログイン')  # ログインリンクが消える
      expect(page).to have_content '山田太郎'  # ユーザー名表示
    end
  end
  
  describe "バリデーション・エラー処理" do
    it "未アクティベートユーザーはログインできない" do
      # 未アクティベートユーザーを作成
      user = create(:user,
        email: 'unactivated@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: '未認証太郎'
      )
      
      visit login_path
      fill_in 'email', with: 'unactivated@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      expect(page).to have_current_path(login_path)
      expect(page).to have_selector('[data-testid="login-error-message"]')  # エラーメッセージ表示
      expect(page).to have_content 'メールアドレスまたはパスワードが正しくありません'  # 具体的なエラー内容
    end
    
    it "存在しないメールアドレスではログインできない" do
      visit login_path
      fill_in 'email', with: 'nonexistent@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      expect(page).to have_current_path(login_path)
      expect(page).to have_selector('[data-testid="login-error-message"]')  # エラーメッセージ表示
      expect(page).to have_content 'メールアドレスまたはパスワードが正しくありません'  # 具体的なエラー内容
    end
    
    it "間違ったパスワードではログインできない" do
      # 正常なアクティベート済みユーザーを作成
      user = create(:user, :activated,
        email: 'wrong_password_test@example.com',
        password: 'correct_password',
        password_confirmation: 'correct_password',
        name: 'パスワードテスト太郎'
      )
      
      visit login_path
      fill_in 'email', with: 'wrong_password_test@example.com'
      fill_in 'password', with: 'wrong_password'
      find('[data-testid="login-submit"]').click
      
      expect(page).to have_current_path(login_path)
      expect(page).to have_selector('[data-testid="login-error-message"]')  # エラーメッセージ表示
      expect(page).to have_content 'メールアドレスまたはパスワードが正しくありません'  # 具体的なエラー内容
    end
    
    it "無効な認証コードでは認証できない" do
      # 第1段階認証用ユーザー
      user = create(:user, :activated,
        email: 'auth_code_test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: '認証コードテスト太郎'
      )
      
      # 第1段階認証を通過
      visit login_path
      fill_in 'email', with: 'auth_code_test@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      # 無効な認証コードを入力
      fill_in 'auth_code', with: '999999'
      find('[data-testid="auth-code-submit"]').click
      
      expect(page).to have_current_path(login_verify_path)
      expect(page).to have_selector('[data-testid="auth-code-error-message"]')  # エラーメッセージ表示
      expect(page).to have_content '認証コードが正しくありません'  # 具体的なエラー内容
    end
  end
  
  describe "ログアウト機能" do
    it "ログアウトが正常に動作する" do
      # ログアウトテスト用ユーザー
      user = create(:user, :activated,
        email: 'logout_test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: 'ログアウトテスト太郎'
      )
      
      # ログインフロー実行
      visit login_path
      fill_in 'email', with: 'logout_test@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      user.reload
      fill_in 'auth_code', with: user.auth_code
      find('[data-testid="auth-code-submit"]').click
      
      # ログアウト実行（:rack_test用の直接的なDELETEリクエスト）
      page.driver.submit :delete, logout_path, {}
      
      expect(page).to have_current_path(root_path)
      # ログアウト成功確認（状態変化で判定）
      expect(page).not_to have_selector('[data-testid="logged-in-user-info"]')  # ログイン状態表示が消える
      expect(page).not_to have_selector('[data-testid="logout-button"]')  # ログアウトボタンが消える
      expect(page).to have_link('ログイン')  # ログインリンクが再表示
      expect(page).not_to have_content 'ログアウトテスト太郎'  # ユーザー名が非表示
    end
  end
  
  describe "セッション管理" do
    it "既にログインしている場合は再ログイン画面を表示しない" do
      # セッション管理テスト用ユーザー
      user = create(:user, :activated,
        email: 'session_test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        name: 'セッション太郎'
      )
      
      # ログインを完了
      visit login_path
      fill_in 'email', with: 'session_test@example.com'
      fill_in 'password', with: 'password123'
      find('[data-testid="login-submit"]').click
      
      user.reload
      fill_in 'auth_code', with: user.auth_code
      find('[data-testid="auth-code-submit"]').click
      
      # 再度ログイン画面にアクセス
      visit login_path
      
      expect(page).to have_current_path(root_path)
      # 既にログイン済み確認（状態変化で判定）
      expect(page).to have_selector('[data-testid="logged-in-user-info"]')  # ログイン状態が維持
      expect(page).to have_selector('[data-testid="logout-button"]')  # ログアウトボタンが表示
    end
  end
end