require 'rails_helper'

RSpec.describe "User Registration", type: :system do
  describe "会員登録フロー" do
    it "新規会員登録から本登録完了まで正常に動作する" do
      # 1. 新規登録画面にアクセス
      visit users_new_path
      expect(page).to have_content '新規会員登録'
      
      # 2. 必須項目を入力（ユニークなメールアドレス使用）
      unique_email = "registration_test_#{Time.current.to_i}@example.com"
      fill_in 'user_email', with: unique_email
      fill_in 'user_password', with: 'password123'
      fill_in 'user_password_confirmation', with: 'password123'
      fill_in 'user_name', with: '山田太郎'
      
      # 3. 確認画面へ進む（POST → 直接表示）
      click_button '確認画面へ'
      
      # 4. 確認画面が表示され、内容を確認（リダイレクトなし）
      # 【参考】パス確認の2つの書き方:
      # expect(current_path).to eq users_new_confirm_path  # 即座チェック
      expect(page).to have_current_path(users_new_confirm_path)  # 自動待機機能付き
      expect(page).to have_content '登録内容の確認'
      expect(page).to have_content unique_email
      expect(page).to have_content '山田太郎'
      
      # 5. 仮登録を実行
      expect {
        click_button '登録する'
      }.to change(User, :count).by(1)
      
      # 6. 仮登録完了画面の確認
      expect(page).to have_content '仮登録が完了しました'
      expect(page).to have_content unique_email
      
      # 7. メール送信確認（ActionMailerのdeliveriesを使用）
      expect(ActionMailer::Base.deliveries.count).to eq(1)
      sent_email = ActionMailer::Base.deliveries.last
      expect(sent_email.to).to include(unique_email)
      expect(sent_email.subject).to include('メール認証')
      
      # 8. ユーザー作成確認
      user = User.find_by(email: unique_email)
      expect(user).to be_present
      expect(user.activated?).to be_falsy
      expect(user.activation_token).to be_present
      
      # 9. 仮登録後の画面確認
      expect(page).to have_current_path(users_new_complete_path)
      expect(page).to have_content '仮登録が完了しました'
    end
    
    it "確認画面から修正して再度確認画面に戻れる" do
      # 1. 確認画面まで進む（ユニークなメールアドレスを使用）
      unique_email = "modify_test_#{Time.current.to_i}@example.com"
      visit users_new_path
      fill_in 'user_email', with: unique_email
      fill_in 'user_password', with: 'password123'
      fill_in 'user_password_confirmation', with: 'password123'
      fill_in 'user_name', with: '山田太郎'
      click_button '確認画面へ'
      
      # 2. 修正リンクをクリック
      click_link '内容を修正する'
      
      # 3. フォームに元の値が復元されている
      expect(find_field('user_email').value).to eq unique_email
      expect(find_field('user_name').value).to eq '山田太郎'
      
      # 4. 修正して再度確認（パスワードも再入力が必要）
      fill_in 'user_password', with: 'password123'
      fill_in 'user_password_confirmation', with: 'password123'
      fill_in 'user_name', with: '田中次郎'
      click_button '確認画面へ'
      
      # 5. 確認画面が表示され、修正された内容が表示される
      expect(page).to have_current_path(users_new_confirm_path)
      expect(page).to have_content '田中次郎'
    end
  end
  
  describe "アクティベーション" do
    let(:user) { create(:user, :with_activation_token) }
    
    it "有効なトークンでアクティベーションが成功する" do
      visit users_activate_path(token: user.activation_token)
      
      expect(page).to have_content '本登録が完了しました'
      
      user.reload
      expect(user.activated?).to be_truthy
      expect(user.activated_at).to be_present
    end
    
    it "無効なトークンでアクティベーションが失敗する" do
      visit users_activate_path(token: 'invalid_token')
      
      expect(page).to have_content '無効なアクティベーションリンクです'
    end
  end
  
  describe "バリデーション" do
    before do
      visit users_new_path
    end
    
    it "必須項目が空の場合にエラーメッセージが表示される" do
      # 直接POSTリクエストを送信してサーバーサイドバリデーションをテスト
      page.driver.submit :post, users_new_confirm_path, {
        'user[email]' => '',
        'user[password]' => '',
        'user[password_confirmation]' => '',
        'user[name]' => ''
      }
      
      expect(page).to have_content 'Email メールアドレスを入力してください'
      expect(page).to have_content 'Password パスワードを入力してください'
    end
    
    it "パスワード確認が一致しない場合にエラーメッセージが表示される" do
      fill_in 'user_email', with: 'test@example.com'
      fill_in 'user_password', with: 'password123'
      fill_in 'user_password_confirmation', with: 'different'
      
      click_button '確認画面へ'
      
      expect(page).to have_content 'パスワード（確認）とパスワードの入力が一致しません'
    end
    
    it "既に登録済みのメールアドレスの場合にエラーメッセージが表示される" do
      create(:user, email: 'existing@example.com')
      
      fill_in 'user_email', with: 'existing@example.com'
      fill_in 'user_password', with: 'password123'
      fill_in 'user_password_confirmation', with: 'password123'
      
      click_button '確認画面へ'
      
      expect(page).to have_content 'メールアドレスはすでに存在します'
    end
  end
  
  before(:each) do
    # ActionMailerの配信をテスト用に設定
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear
  end
end