# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      # Basic認証
      before_action :authenticate_relying_party

      # GET /api/v1/users
      # ユーザー検索
      def index
        # パラメータ検証
        if params[:ids].blank? && params[:name].blank? && params[:kana_name].blank? && params[:phone_number].blank?
          return render json: {
            error: 'Missing parameter',
            message: 'ids, name, kana_name, phone_number のいずれかが必要です'
          }, status: :bad_request
        end

        # limit/offset
        limit = [params[:limit].to_i, 1000].min
        limit = 100 if limit <= 0
        offset = [params[:offset].to_i, 0].max

        # 検索条件構築
        users = User.where(deleted_at: nil)

        # RP絞り込み条件
        if params[:registered_only] == 'true' || params[:activated_only] == 'true'
          users = users.joins(:user_relying_parties)
                       .where(user_relying_parties: { relying_party_id: @current_relying_party.id })

          # 利用中（activated）のみ
          if params[:activated_only] == 'true'
            users = users.where.not(user_relying_parties: { activated_at: nil })
          end
        end

        if params[:ids].present?
          # IDs検索
          ids = params[:ids].split(',').map(&:to_i).reject(&:zero?)
          users = users.where(id: ids)
        elsif params[:name].present?
          # 氏名（漢字）部分一致
          name = params[:name]
          users = users.where(
            'CONCAT(last_name, first_name) LIKE ? OR CONCAT(last_name, " ", first_name) LIKE ?',
            "%#{name}%", "%#{name}%"
          )
        elsif params[:kana_name].present?
          # 氏名（かな）部分一致
          kana_name = params[:kana_name]
          users = users.where(
            'CONCAT(last_kana_name, first_kana_name) LIKE ? OR CONCAT(last_kana_name, " ", first_kana_name) LIKE ?',
            "%#{kana_name}%", "%#{kana_name}%"
          )
        elsif params[:phone_number].present?
          # 電話番号完全一致（ハイフン除去して比較）
          normalized_phone = params[:phone_number].gsub(/[-\s]/, '')
          users = users.where('REPLACE(REPLACE(phone_number, "-", ""), " ", "") = ?', normalized_phone)
        end

        users = users.limit(limit).offset(offset)

        render json: users.map { |u| user_response(u) }, status: :ok
      rescue StandardError => e
        Rails.logger.error "Api::V1::UsersController#index failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          error: 'Internal server error',
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      # GET /api/v1/users/:id
      # ユーザーID指定取得
      def show
        user = User.find_by(id: params[:id])

        unless user
          return render json: {
            error: 'User not found',
            message: '指定されたユーザーは存在しません'
          }, status: :not_found
        end

        # 論理削除されたユーザーは404扱い
        if user.deleted_at.present?
          return render json: {
            error: 'User not found',
            message: '指定されたユーザーは存在しません'
          }, status: :not_found
        end

        render json: user_response(user), status: :ok
      rescue StandardError => e
        Rails.logger.error "Api::V1::UsersController#show failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          error: 'Internal server error',
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      # POST /api/v1/users
      # ユーザー新規作成/更新
      def create
        # Form Objectでバリデーション
        form = Api::V1::UserForm.initialize_from_api_params(params)

        unless form.valid?
          return render json: { errors: form.errors.full_messages }, status: :unprocessable_entity
        end

        # ID指定の有無で処理分岐
        if params[:id].present?
          # 更新処理
          update_user_with_id(form)
        else
          # 新規作成処理
          create_new_user(form)
        end
      rescue StandardError => e
        Rails.logger.error "Api::V1::UsersController#create failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          error: 'Internal server error',
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      # PATCH /api/v1/users/:id
      # ユーザー部分更新
      def update
        # ユーザー検索
        user = User.find_by(id: params[:id])
        return render_not_found unless user

        # 論理削除されたユーザーは404扱い
        return render_not_found if user.deleted_at.present?

        # 部分更新用のパラメータ取得
        permitted_params = params.permit(
          :email, :password, :password_confirmation,
          :last_name, :first_name, :has_middle_name, :middle_name,
          :last_kana_name, :first_kana_name,
          :birth_date, :gender_code, :gender_text,
          :phone_number,
          :home_is_address_selected_manually,
          :home_postal_code, :home_prefecture_code, :home_master_city_id,
          :home_address_town, :home_address_later,
          :employment_status,
          :workplace_name, :workplace_phone_number,
          :workplace_is_address_selected_manually,
          :workplace_postal_code, :workplace_prefecture_code, :workplace_master_city_id,
          :workplace_address_town, :workplace_address_later,
          metadata: {}
        )

        # トランザクション: users更新 + user_relying_parties更新
        ActiveRecord::Base.transaction do
          # プロフィール更新
          update_attrs = permitted_params.except(:metadata)
          user.update!(update_attrs) if update_attrs.present?
          user.update!(updated_by: @current_relying_party)

          # metadata 更新（RP API経由なのでactivate: false）
          if permitted_params[:metadata].present?
            UserRelyingPartyService.create_or_update(
              user: user,
              relying_party: @current_relying_party,
              metadata: permitted_params[:metadata],
              activate: false
            )
          end
        end

        render json: user_response(user), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error "Api::V1::UsersController#update failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          error: 'Internal server error',
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      private

      # Basic認証
      def authenticate_relying_party
        authenticate_or_request_with_http_basic do |api_key, api_secret|
          @current_relying_party = RelyingParty.active.find_by(api_key: api_key)

          if @current_relying_party.nil?
            render json: {
              error: 'Invalid credentials',
              message: 'api_key が正しくありません'
            }, status: :unauthorized
            return false
          end

          if @current_relying_party.api_secret != api_secret
            render json: {
              error: 'Invalid credentials',
              message: 'api_secret が正しくありません'
            }, status: :unauthorized
            return false
          end

          true
        end
      end

      # ID指定ありの場合の更新処理
      def update_user_with_id(form)
        user = User.find_by(id: params[:id])
        return render_not_found unless user

        # 論理削除されたユーザーは404扱い
        return render_not_found if user.deleted_at.present?

        # トランザクション: users更新 + user_relying_parties更新
        ActiveRecord::Base.transaction do
          user.update!(form.to_user_attributes_with_auth)
          user.update!(updated_by: @current_relying_party)

          # user_relying_parties の作成/更新（RP API経由なのでactivate: false）
          UserRelyingPartyService.create_or_update(
            user: user,
            relying_party: @current_relying_party,
            metadata: params[:metadata] || {},
            activate: false
          )
        end

        render json: user_response(user), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      # 新規作成処理
      def create_new_user(form)
        user = nil
        ActiveRecord::Base.transaction do
          user = User.create!(form.to_user_attributes_with_auth)
          user.update!(created_by: @current_relying_party)

          # user_relying_parties の作成（RP API経由なのでactivate: false）
          UserRelyingPartyService.find_or_create(
            user: user,
            relying_party: @current_relying_party,
            metadata: params[:metadata] || {},
            activate: false
          )
        end

        render json: user_response(user), status: :created
      rescue ActiveRecord::RecordNotUnique => e
        # ユニーク制約違反 → 409 Conflict
        if e.message.include?('email')
          render json: {
            error: 'Email already exists',
            message: 'このメールアドレスは既に登録されています'
          }, status: :conflict
        elsif e.message.include?('phone_number')
          render json: {
            error: 'Phone number already exists',
            message: 'この電話番号は既に登録されています'
          }, status: :conflict
        else
          raise
        end
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      # 404レスポンス
      def render_not_found
        render json: {
          error: 'User not found',
          message: '指定されたユーザーは存在しません'
        }, status: :not_found
      end

      # レスポンス整形（除外カラムを除く）
      def user_response(user)
        # リクエスト元RPに対応するuser_relying_partyを取得
        user_rp = UserRelyingParty.find_by(
          user_id: user.id,
          relying_party_id: @current_relying_party.id
        )

        user.as_json(except: [
          'encrypted_password',
          'mail_authentication_code',
          'mail_authentication_expires_at',
          'reset_password_token',
          'reset_password_sent_at',
          'deleted_at',
          'current_sign_in_at'
        ]).merge(
          'metadata' => user_rp&.metadata || {}
        )
      end
    end
  end
end
