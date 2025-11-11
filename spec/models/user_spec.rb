require 'rails_helper'

RSpec.describe User, type: :model do
  # Shared Examples の定義
  RSpec.shared_examples "valid user creation" do |user_attributes|
    it "有効なユーザーが作成される" do
      user = User.new(user_attributes)
      expect(user).to be_valid
      expect { user.save! }.to change(User, :count).by(1)
      expect(user.persisted?).to be true
    end
  end

  RSpec.shared_examples "invalid user validation" do |invalid_attributes, expected_error_field|
    it "バリデーションエラーが発生する" do
      user = User.new(invalid_attributes)
      expect(user).not_to be_valid
      expect(user.errors[expected_error_field]).to be_present
      expect { user.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "バリデーション" do
    let(:valid_attributes) {
      {
        name: "田中太郎",
        email: "tanaka@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    context "正常なケース" do
      include_examples "valid user creation", {
        name: "田中太郎",
        email: "tanaka@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    end

    context "名前のバリデーション" do
      include_examples "invalid user validation", {
        name: "",
        email: "test@example.com",
        password: "password123",
        password_confirmation: "password123"
      }, :name
    end

    context "メールアドレスのバリデーション" do
      include_examples "invalid user validation", {
        name: "田中太郎",
        email: "",
        password: "password123",
        password_confirmation: "password123"
      }, :email

      include_examples "invalid user validation", {
        name: "田中太郎",
        email: "invalid-email",
        password: "password123",
        password_confirmation: "password123"
      }, :email
    end

    context "パスワードのバリデーション" do
      include_examples "invalid user validation", {
        name: "田中太郎",
        email: "test@example.com",
        password: "short",
        password_confirmation: "short"
      }, :password
    end

    context "メールアドレスの重複" do
      before do
        User.create!(valid_attributes)
      end

      include_examples "invalid user validation", {
        name: "佐藤花子",
        email: "tanaka@example.com", # 重複メール
        password: "password123",
        password_confirmation: "password123"
      }, :email
    end
  end

  describe "認証関連メソッド" do
    let(:user) { User.create!(name: "田中太郎", email: "tanaka@example.com", password: "password123", password_confirmation: "password123") }

    describe "#generate_auth_code!" do
      it "6桁の認証コードが生成される" do
        user.generate_auth_code!
        expect(user.auth_code).to match(/\A\d{6}\z/)
        expect(user.auth_code_expires_at).to be_within(1.second).of(10.minutes.from_now)
      end
    end

    describe "#auth_code_valid?" do
      before { user.generate_auth_code! }

      it "正しい認証コードで成功する" do
        expect(user.auth_code_valid?(user.auth_code)).to be true
      end

      it "間違った認証コードで失敗する" do
        expect(user.auth_code_valid?("999999")).to be false
      end

      it "期限切れで失敗する" do
        user.update!(auth_code_expires_at: 1.minute.ago)
        expect(user.auth_code_valid?(user.auth_code)).to be false
      end
    end

    describe "#clear_auth_code!" do
      before { user.generate_auth_code! }

      it "認証コードがクリアされる" do
        user.clear_auth_code!
        expect(user.auth_code).to be_nil
        expect(user.auth_code_expires_at).to be_nil
      end
    end
  end

  describe "アクティベーション関連メソッド" do
    let(:user) { User.create!(name: "田中太郎", email: "tanaka@example.com", password: "password123", password_confirmation: "password123") }

    describe "#activated?" do
      it "未アクティベート状態では false" do
        expect(user.activated?).to be false
      end

      it "アクティベート済みでは true" do
        user.activate!
        expect(user.activated?).to be true
      end
    end

    describe "#generate_activation_token!" do
      it "アクティベーショントークンが生成される" do
        user.generate_activation_token!
        expect(user.activation_token).to be_present
        expect(user.activation_token.length).to be >= 32
        expect(user.activation_expires_at).to be_within(1.second).of(24.hours.from_now)
      end
    end

    describe "#activation_token_valid?" do
      before { user.generate_activation_token! }

      it "正しいトークンで成功する" do
        expect(user.activation_token_valid?(user.activation_token)).to be true
      end

      it "間違ったトークンで失敗する" do
        expect(user.activation_token_valid?("invalid_token")).to be false
      end

      it "期限切れで失敗する" do
        user.update!(activation_expires_at: 1.hour.ago)
        expect(user.activation_token_valid?(user.activation_token)).to be false
      end
    end

    describe "#activate!" do
      before { user.generate_activation_token! }

      it "アクティベーションが完了する" do
        user.activate!
        expect(user.activated_at).to be_present
        expect(user.activation_token).to be_nil
        expect(user.activation_expires_at).to be_nil
      end
    end
  end

  describe "ログイン関連メソッド" do
    let(:user) { User.create!(name: "田中太郎", email: "tanaka@example.com", password: "password123", password_confirmation: "password123") }

    describe "#update_last_login!" do
      it "最終ログイン時刻が更新される" do
        expect {
          user.update_last_login!
        }.to change { user.reload.last_login_at }
      end
    end

    describe "#last_login_display" do
      context "未ログインの場合" do
        it "「未ログイン」を返す" do
          expect(user.last_login_display).to eq("未ログイン")
        end
      end

      context "ログイン履歴がある場合" do
        before { user.update_last_login! }

        it "適切な表示文字列を返す" do
          expect(user.last_login_display).to match(/\d+分前/)
        end
      end
    end
  end
end