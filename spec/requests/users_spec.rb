require 'rails_helper'

RSpec.describe "Users", type: :request do
  # Model テストの Shared Examples を参照（コメントで示唆）

  # Users API 用の Shared Examples
  RSpec.shared_examples "user registration API" do |user_params, expected_response|
    it "適切なレスポンスを返す" do
      expect {
        post users_new_register_path, params: { user: user_params }
      }.to change(User, :count).by(expected_response[:user_count_change])
      
      expect(response).to have_http_status(expected_response[:status])
      
      if expected_response[:redirects_to]
        expect(response).to redirect_to(expected_response[:redirects_to])
      end
      
      if expected_response[:has_validation_errors]
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /users/new" do
    it "会員登録フォームが表示される" do
      get users_new_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('新規会員登録')
    end
  end

  describe "POST /users/confirm" do
    context "有効なパラメータの場合" do
      let(:valid_params) {
        {
          name: "田中太郎",
          email: "tanaka@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }

      it "確認画面が表示される" do
        post users_new_confirm_path, params: { user: valid_params }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('田中太郎')
        expect(response.body).to include('tanaka@example.com')
        expect(response.body).to include('users/new/register')
      end

      it "ユーザーは作成されない" do
        expect {
          post users_new_confirm_path, params: { user: valid_params }
        }.not_to change(User, :count)
      end
    end

    context "無効なパラメータの場合" do
      let(:invalid_params) {
        {
          name: "",
          email: "invalid-email",
          password: "short",
          password_confirmation: "different"
        }
      }

      it "入力フォームに戻る" do
        post users_new_confirm_path, params: { user: invalid_params }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('users/new/confirm')
      end

      it "エラーメッセージが表示される" do
        post users_new_confirm_path, params: { user: invalid_params }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('users/new')  # フォームが再表示される
      end
    end
  end

  describe "POST /users" do
    context "正常な会員登録" do
      # Model テストと同じ値を使用
      include_examples "user registration API", {
        name: "田中太郎",
        email: "tanaka@example.com",
        password: "password123", 
        password_confirmation: "password123"
      }, {
        user_count_change: 1,
        status: :found, # リダイレクト
        redirects_to: nil # 動的に計算される
      }

      it "アクティベーションメールが送信される" do
        expect {
          post users_path, params: {
            user: {
              name: "田中太郎",
              email: "tanaka@example.com", 
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.to have_enqueued_mail(UserMailer, :activation_email)
      end

      it "成功メッセージが設定される" do
        post users_path, params: {
          user: {
            name: "田中太郎", 
            email: "tanaka@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
        expect(response).to have_http_status(:found)
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end
    end

    context "バリデーションエラー" do
      include_examples "user registration API", {
        name: "",
        email: "invalid-email",
        password: "short",
        password_confirmation: "different"
      }, {
        user_count_change: 0,
        status: :unprocessable_entity,
        redirects_to: nil,
        has_validation_errors: true
      }
    end

    context "メールアドレス重複" do
      before do
        User.create!(
          name: "既存ユーザー",
          email: "duplicate@example.com",
          password: "password123",
          password_confirmation: "password123"
        )
      end

      include_examples "user registration API", {
        name: "新規ユーザー", 
        email: "duplicate@example.com",
        password: "password123",
        password_confirmation: "password123"
      }, {
        user_count_change: 0,
        status: :unprocessable_entity,
        redirects_to: nil,
        has_validation_errors: true
      }
    end
  end

  describe "GET /users/:token/activate" do
    let(:user) { 
      User.create!(
        name: "田中太郎",
        email: "tanaka@example.com", 
        password: "password123",
        password_confirmation: "password123"
      )
    }

    context "有効なトークンの場合" do
      before { user.generate_activation_token! }

      it "アクティベーションが成功する" do
        get users_activate_path(token: user.activation_token)
        
        expect(response).to redirect_to(users_activated_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
        
        user.reload
        expect(user.activated?).to be true
      end
    end

    context "無効なトークンの場合" do
      it "エラーメッセージが表示される" do
        get users_activate_path(token: "invalid_token")
        
        expect(response).to have_http_status(:not_found)
      end
    end

    context "期限切れトークンの場合" do
      before do
        user.generate_activation_token!
        user.update!(activation_expires_at: 1.hour.ago)
      end

      it "エラーメッセージが表示される" do
        get users_activate_path(token: user.activation_token)
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "統合テスト: 完全な会員登録フロー" do
    it "フォーム表示→確認→登録→アクティベーション の完全フロー" do
      # 1. フォーム表示
      get users_new_path
      expect(response).to have_http_status(:ok)

      # 2. 確認画面
      post users_confirm_path, params: {
        user: {
          name: "完全フロー太郎",
          email: "full_flow@example.com",
          password: "password123", 
          password_confirmation: "password123"
        }
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('完全フロー太郎')

      # 3. ユーザー登録実行
      expect {
        post users_new_register_path, params: {
          user: {
            name: "完全フロー太郎",
            email: "full_flow@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:found)
      
      # 作成されたユーザーの確認
      user = User.find_by(email: "full_flow@example.com")
      expect(user).to be_present
      expect(user.name).to eq("完全フロー太郎") 
      expect(user.activated?).to be false
      expect(user.activation_token).to be_present

      # 4. アクティベーション実行
      get users_activate_path(token: user.activation_token)
      expect(response).to redirect_to(users_activated_path)
      
      user.reload
      expect(user.activated?).to be true
      expect(user.activation_token).to be_nil
    end
  end
end