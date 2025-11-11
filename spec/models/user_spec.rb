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
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "tanaka@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      }
    }

    context "正常なケース" do
      include_examples "valid user creation", {
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "tanaka@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      }
    end

    context "名前のバリデーション" do
      include_examples "invalid user validation", {
        last_name: "",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "test@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      }, :last_name

      include_examples "invalid user validation", {
        last_name: "田中",
        first_name: "",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "test@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      }, :first_name
    end

    context "メールアドレスのバリデーション" do
      include_examples "invalid user validation", {
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "invalid-email",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      }, :email
    end

    context "就労状況のバリデーション" do
      include_examples "invalid user validation", {
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "test@example.com",
        employment_status: nil,
        password: "password123",
        password_confirmation: "password123"
      }, :employment_status
    end

    context "パスワードのバリデーション" do
      include_examples "invalid user validation", {
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "test@example.com",
        employment_status: 1,
        password: "short",
        password_confirmation: "short"
      }, :password
    end
  end

  describe "メール認証コード関連メソッド" do
    let(:user) do
      User.create!(
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "tanaka@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      )
    end

    describe "#generate_mail_authentication_code!" do
      it "6桁の認証コードが生成される" do
        user.generate_mail_authentication_code!
        expect(user.mail_authentication_code).to be_between(100000, 999999)
        expect(user.mail_authentication_expires_at).to be_within(1.second).of(10.minutes.from_now)
      end
    end

    describe "#mail_authentication_code_valid?" do
      before { user.generate_mail_authentication_code! }

      it "正しい認証コードで成功する" do
        expect(user.mail_authentication_code_valid?(user.mail_authentication_code)).to be true
      end

      it "間違った認証コードで失敗する" do
        expect(user.mail_authentication_code_valid?(999999)).to be false
      end

      it "期限切れで失敗する" do
        user.update!(mail_authentication_expires_at: 1.minute.ago)
        expect(user.mail_authentication_code_valid?(user.mail_authentication_code)).to be false
      end
    end

    describe "#clear_mail_authentication_code!" do
      before { user.generate_mail_authentication_code! }

      it "認証コードがクリアされる" do
        user.clear_mail_authentication_code!
        expect(user.mail_authentication_code).to be_nil
        expect(user.mail_authentication_expires_at).to be_nil
      end
    end
  end

  describe "ログイン関連メソッド" do
    let(:user) do
      User.create!(
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "tanaka@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      )
    end

    describe "#update_last_sign_in!" do
      it "最終ログイン時刻が更新される" do
        expect {
          user.update_last_sign_in!
        }.to change { user.reload.last_sign_in_at }
      end
    end

    describe "#last_sign_in_display" do
      context "未ログインの場合" do
        it "「未ログイン」を返す" do
          expect(user.last_sign_in_display).to eq("未ログイン")
        end
      end

      context "ログイン履歴がある場合" do
        before { user.update_last_sign_in! }

        it "適切な表示文字列を返す" do
          expect(user.last_sign_in_display).to match(/\d+分前/)
        end
      end
    end
  end

  describe "名前関連メソッド" do
    let(:user) do
      User.create!(
        last_name: "田中",
        first_name: "太郎",
        last_kana_name: "たなか",
        first_kana_name: "たろう",
        email: "tanaka@example.com",
        employment_status: 1,
        password: "password123",
        password_confirmation: "password123"
      )
    end

    describe "#full_name" do
      it "フルネームを返す" do
        expect(user.full_name).to eq("田中 太郎")
      end

      context "ミドルネームがある場合" do
        before do
          user.update!(has_middle_name: 1, middle_name: "ジョン")
        end

        it "ミドルネームを含むフルネームを返す" do
          expect(user.full_name).to eq("田中 ジョン 太郎")
        end
      end
    end

    describe "#full_kana_name" do
      it "フルネーム（かな）を返す" do
        expect(user.full_kana_name).to eq("たなか たろう")
      end
    end
  end
end