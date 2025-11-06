# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /users/api/sign_up/email", type: :request do
  describe "正常系" do
    it "有効なメールアドレスでSignupTicketが作成される" do
      post '/users/api/sign_up/email', params: {
        email: 'newuser@example.com'
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['token']).to be_present
      expect(json['message']).to include('確認メールを送信しました')
    end
  end

  describe "異常系" do
    context "メールアドレスが空の場合" do
      it "バリデーションエラーが返される" do
        post '/users/api/sign_up/email', params: {
          email: ''
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['email']).to be_present
      end
    end

    context "重複するメールアドレスの場合" do
      let!(:existing_user) { create(:user, email: 'existing@example.com') }

      it "バリデーションエラーが返される" do
        post '/users/api/sign_up/email', params: {
          email: 'existing@example.com'
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['email'].first).to include('既に登録されています')
      end
    end
  end
end
