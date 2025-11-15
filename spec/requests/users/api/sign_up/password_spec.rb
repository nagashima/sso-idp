# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "POST /users/api/sign_up/password", type: :request do
  let(:signup_ticket) { create(:signup_ticket, email: 'test@example.com', confirmed_at: Time.current) }

  describe "正常系" do
    it "有効なトークンとパスワードで保存される" do
      post '/users/api/sign_up/password', params: {
        token: signup_ticket.token,
        password: 'password123',
        password_confirmation: 'password123'
      }, as: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end
  end

  describe "異常系" do
    context "パスワードが8文字未満の場合" do
      it "バリデーションエラーが返される" do
        post '/users/api/sign_up/password', params: {
          token: signup_ticket.token,
          password: 'short'
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']['password']).to be_present
      end
    end
  end
end
