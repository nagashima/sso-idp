# frozen_string_literal: true

module Api
  module Common
    # 住所検索API（共通）
    # 郵便番号検索、都道府県・市区町村マスタ取得
    class AddressSearchController < ApplicationController
      # POST /api/common/address_search
      # 郵便番号から住所を検索（自動入力モード用）
      def index
        postal_code = params[:postal_code]

        if postal_code.blank?
          return render json: {
            status: 400,
            message: '郵便番号を入力してください'
          }, status: :bad_request
        end

        # Zipcloud APIで検索
        zipcloud_result = PostalCodeService.search(postal_code: postal_code)

        unless zipcloud_result
          return render json: {
            status: 500,
            message: '郵便番号検索サービスでエラーが発生しました'
          }, status: :internal_server_error
        end

        # ステータスチェック
        if zipcloud_result['status'] != 200
          return render json: {
            status: zipcloud_result['status'],
            message: zipcloud_result['message'] || '郵便番号が見つかりませんでした'
          }, status: :ok
        end

        # 結果がない場合
        if zipcloud_result['results'].blank?
          return render json: {
            status: 404,
            message: '該当する住所が見つかりませんでした'
          }, status: :ok
        end

        # マスタデータと照合
        results = CityService.compare(zipcloud_result['results'])

        render json: {
          status: 200,
          results: results
        }
      rescue StandardError => e
        Rails.logger.error "AddressSearchController#index failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: {
          status: 500,
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      # GET /api/common/address_search/prefectures
      # 都道府県一覧取得（手動入力モード用）
      def prefectures
        prefectures = PrefectureService.all

        render json: {
          status: 200,
          results: prefectures.map { |p| { id: p.id, name: p.name } }
        }
      rescue StandardError => e
        Rails.logger.error "AddressSearchController#prefectures failed: #{e.message}"
        render json: {
          status: 500,
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end

      # GET /api/common/address_search/cities
      # 都道府県IDから市区町村一覧取得（手動入力モード用）
      # params: master_prefecture_id
      def cities
        prefecture_id = params[:master_prefecture_id]

        if prefecture_id.blank?
          return render json: {
            status: 400,
            message: '都道府県IDが必要です'
          }, status: :bad_request
        end

        cities = CityService.fetch_by_master_prefecture_id(prefecture_id)

        render json: {
          status: 200,
          results: cities.map { |c|
            {
              id: c.id,
              name: CityService.get_name(c.id)  # 郡名も含めた表示名
            }
          }
        }
      rescue StandardError => e
        Rails.logger.error "AddressSearchController#cities failed: #{e.message}"
        render json: {
          status: 500,
          message: 'システムエラーが発生しました'
        }, status: :internal_server_error
      end
    end
  end
end
