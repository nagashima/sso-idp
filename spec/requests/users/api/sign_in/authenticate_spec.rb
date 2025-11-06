# frozen_string_literal: true

require 'rails_helper'

# RSpec.describe: 何をテストするかを宣言
# type: :request は「Request Spec（HTTPテスト）」という意味
RSpec.describe "POST /users/api/sign_in/authenticate", type: :request do
  # テストで使う変数を定義（beforeブロックで実行される前に用意される）
  let(:user) { create(:user, email: 'test@example.com', password: 'password123', password_confirmation: 'password123') }

  # describe: テストのグループ分け（正常系）
  describe "正常系" do
    # before: テストの前に実行される準備処理
    before do
      user.activate! # ユーザーをアクティベート（有効化）
    end

    # it: 1つのテストケース（期待する動作を書く）
    it "有効な認証情報でtemp_tokenが返される" do
      # ===== 準備（Arrange）=====
      # user は let で定義済み

      # ===== 実行（Act）=====
      # POST リクエストを送信
      post '/users/api/sign_in/authenticate', params: {
        email: 'test@example.com',
        password: 'password123'
      }, as: :json  # as: :json は「JSONリクエストとして送る」という意味

      # ===== 検証（Assert）=====
      # レスポンスのステータスコードが200 OKかチェック
      expect(response).to have_http_status(:ok)

      # レスポンスのJSONをパース（Rubyのハッシュに変換）
      json = JSON.parse(response.body)

      # temp_tokenが含まれているかチェック
      expect(json['temp_token']).to be_present

      # statusが'awaiting_2fa'かチェック
      expect(json['status']).to eq('awaiting_2fa')

      # flow_typeが'web'かチェック
      expect(json['flow_type']).to eq('web')
    end
  end

  # describe: テストのグループ分け（異常系）
  describe "異常系" do
    # context: さらに細かいシナリオ分け
    context "メールアドレスが空の場合" do
      it "バリデーションエラーが返される" do
        # POSTリクエスト送信（メールが空）
        post '/users/api/sign_in/authenticate', params: {
          email: '',
          password: 'password123'
        }, as: :json

        # ステータスコードが422 Unprocessable Contentかチェック
        expect(response).to have_http_status(:unprocessable_content)

        # レスポンスのJSONをパース
        json = JSON.parse(response.body)

        # エラーメッセージにemailのエラーが含まれているかチェック
        expect(json['errors']['email']).to be_present
      end
    end

    context "パスワードが間違っている場合" do
      before do
        user.activate!
      end

      it "認証エラーが返される" do
        post '/users/api/sign_in/authenticate', params: {
          email: 'test@example.com',
          password: 'wrong_password'  # 間違ったパスワード
        }, as: :json

        # ステータスコードが422かチェック
        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)

        # base（全体）エラーが含まれているかチェック
        expect(json['errors']['base']).to be_present
      end
    end

    context "ユーザーが未アクティベートの場合" do
      # before を書かない = user.activate! しない = 未アクティベート状態

      it "アクティベーションエラーが返される" do
        post '/users/api/sign_in/authenticate', params: {
          email: 'test@example.com',
          password: 'password123'
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['base']).to be_present
      end
    end
  end
end
