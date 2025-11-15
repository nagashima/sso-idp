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
