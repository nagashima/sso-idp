require 'rails_helper'

RSpec.describe "User Registration Simple", type: :system do
  before(:each) do
    # ActionMailerの配信をテスト用に設定
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear
  end

  describe "基本的な会員登録フロー" do
    it "新規会員登録フォームが表示される" do
      # 1. 新規登録画面にアクセス
      visit users_new_path
      expect(page).to have_content '新規会員登録'
      
      # 2. 必要なフォーム要素が存在する
      expect(page).to have_field('メールアドレス')
      expect(page).to have_field('パスワード')
      expect(page).to have_field('パスワード確認')
      expect(page).to have_field('氏名')
      expect(page).to have_button('確認画面へ')
    end
  end
end