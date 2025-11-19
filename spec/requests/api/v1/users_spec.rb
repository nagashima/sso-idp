# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "API V1 Users", type: :request do
  let(:relying_party) { create(:relying_party) }
  let(:auth_header) do
    ActionController::HttpAuthentication::Basic.encode_credentials(
      relying_party.api_key,
      relying_party.api_secret
    )
  end
  let(:valid_user_params) do
    {
      email: 'newuser@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      last_name: '田中',
      first_name: '花子',
      last_kana_name: 'たなか',
      first_kana_name: 'はなこ',
      has_middle_name: 0,
      birth_date: '1995-05-15',
      gender_code: 2,
      phone_number: '080-9999-8888',
      home_is_address_selected_manually: 0,
      home_postal_code: '1500001',
      home_prefecture_code: 13,
      home_master_city_id: 131016,  # 東京都千代田区
      home_address_town: '渋谷',
      home_address_later: '1-1-1',
      employment_status: 2,
      metadata: { custom_field: 'test_value' }
    }
  end

  describe "POST /api/v1/users (ID未指定)" do
    context "正常系: 新規作成" do
      it "ユーザーが作成され、201 Createdが返される" do
        post '/api/v1/users',
             params: valid_user_params,
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json['email']).to eq('newuser@example.com')
        expect(json['last_name']).to eq('田中')
        expect(json['metadata']).to eq({ 'custom_field' => 'test_value' })
      end

      it "created_byが設定される" do
        post '/api/v1/users',
             params: valid_user_params,
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:created)

        user = User.last
        expect(user.created_by.id).to eq(relying_party.id)
      end

      it "user_relying_partiesにmetadataが保存される" do
        post '/api/v1/users',
             params: valid_user_params,
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:created)

        user = User.last
        user_rp = UserRelyingParty.find_by(user_id: user.id, relying_party_id: relying_party.id)
        expect(user_rp).to be_present
        expect(user_rp.metadata).to eq({ 'custom_field' => 'test_value' })
      end
    end

    context "異常系: email重複" do
      let!(:existing_user) { create(:user, email: 'duplicate@example.com') }

      it "409 Conflictが返される" do
        post '/api/v1/users',
             params: valid_user_params.merge(email: 'duplicate@example.com'),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:conflict)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('Email already exists')
        expect(json['message']).to include('既に登録されています')
      end
    end

    context "異常系: phone_number重複" do
      let!(:existing_user) { create(:user, phone_number: '09011112222') }

      # TODO: phone_numberにユニーク制約を追加後にテストを有効化
      xit "409 Conflictが返される" do
        post '/api/v1/users',
             params: valid_user_params.merge(phone_number: '090-1111-2222'),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:conflict)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('Phone number already exists')
        expect(json['message']).to include('既に登録されています')
      end
    end

    context "異常系: バリデーションエラー" do
      it "必須項目が不足している場合、422 Unprocessable Entityが返される" do
        post '/api/v1/users',
             params: { email: 'test@example.com' },
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
      end
    end

    context "異常系: 認証失敗" do
      it "認証情報が不正な場合、401 Unauthorizedが返される" do
        post '/api/v1/users',
             params: valid_user_params,
             headers: { 'Authorization' => 'Basic invalid' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/users (ID指定)" do
    let!(:existing_user) { create(:user, email: 'existing@example.com') }

    context "正常系: 更新" do
      it "ユーザーが更新され、200 OKが返される" do
        post '/api/v1/users',
             params: valid_user_params.merge(id: existing_user.id),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['id']).to eq(existing_user.id)
        expect(json['email']).to eq('newuser@example.com')
        expect(json['last_name']).to eq('田中')
      end

      it "updated_byが設定される" do
        post '/api/v1/users',
             params: valid_user_params.merge(id: existing_user.id),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:ok)

        existing_user.reload
        expect(existing_user.updated_by.id).to eq(relying_party.id)
      end

      it "user_relying_partiesのmetadataが更新される" do
        post '/api/v1/users',
             params: valid_user_params.merge(id: existing_user.id),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:ok)

        user_rp = UserRelyingParty.find_by(user_id: existing_user.id, relying_party_id: relying_party.id)
        expect(user_rp).to be_present
        expect(user_rp.metadata).to eq({ 'custom_field' => 'test_value' })
      end
    end

    context "異常系: ID不在" do
      it "404 Not Foundが返される" do
        post '/api/v1/users',
             params: valid_user_params.merge(id: 99999),
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('User not found')
      end
    end

    context "異常系: バリデーションエラー" do
      it "不正なデータの場合、422 Unprocessable Entityが返される" do
        post '/api/v1/users',
             params: { id: existing_user.id, last_name: '' },
             headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
      end
    end
  end

  describe "PATCH /api/v1/users/:id" do
    let!(:existing_user) { create(:user, email: 'existing@example.com') }

    context "正常系: 部分更新" do
      it "送信されたフィールドのみ更新され、200 OKが返される" do
        patch "/api/v1/users/#{existing_user.id}",
              params: { last_name: '佐藤', phone_number: '080-7777-6666' },
              headers: { 'Authorization' => auth_header },
              as: :json

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['last_name']).to eq('佐藤')
        expect(json['phone_number']).to eq('080-7777-6666')
        expect(json['email']).to eq('existing@example.com') # 変更されていない
      end

      it "updated_byが設定される" do
        patch "/api/v1/users/#{existing_user.id}",
              params: { last_name: '佐藤' },
              headers: { 'Authorization' => auth_header },
             as: :json

        expect(response).to have_http_status(:ok)

        existing_user.reload
        expect(existing_user.updated_by.id).to eq(relying_party.id)
      end

      it "metadataが更新される" do
        patch "/api/v1/users/#{existing_user.id}",
              params: { metadata: { new_field: 'new_value' } },
              headers: { 'Authorization' => auth_header },
              as: :json

        expect(response).to have_http_status(:ok)

        user_rp = UserRelyingParty.find_by(user_id: existing_user.id, relying_party_id: relying_party.id)
        expect(user_rp).to be_present
        expect(user_rp.metadata).to eq({ 'new_field' => 'new_value' })
      end
    end

    context "異常系: ID不在" do
      it "404 Not Foundが返される" do
        patch "/api/v1/users/99999",
              params: { last_name: '佐藤' },
              headers: { 'Authorization' => auth_header },
              as: :json

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)
        expect(json['error']).to eq('User not found')
      end
    end

    context "異常系: バリデーションエラー" do
      it "不正なデータの場合、422 Unprocessable Entityが返される" do
        patch "/api/v1/users/#{existing_user.id}",
              params: { email: 'invalid-email' },
              headers: { 'Authorization' => auth_header },
              as: :json

        expect(response).to have_http_status(:unprocessable_content)

        json = JSON.parse(response.body)
        expect(json['errors']).to be_present
      end
    end

    context "異常系: 認証失敗" do
      it "認証情報が不正な場合、401 Unauthorizedが返される" do
        patch "/api/v1/users/#{existing_user.id}",
              params: { last_name: '佐藤' },
              headers: { 'Authorization' => 'Basic invalid' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
