# 郵便番号から住所を検索するサービス
#
# 内部でZipcloud APIを使用していますが、将来的に別のAPIに切り替え可能なように
# サービス名は技術名ではなく機能名（PostalCodeService）としています。
#
# Zipcloud API仕様:
# - エンドポイント: https://zipcloud.ibsnet.co.jp/api/search
# - パラメータ: zipcode（ハイフンなし7桁の郵便番号）
# - レスポンス: JSON形式
class PostalCodeService
  # Zipcloud APIのエンドポイント
  API_ENDPOINT = 'https://zipcloud.ibsnet.co.jp/api/search'.freeze

  # APIタイムアウト設定（秒）
  TIMEOUT_SECONDS = 5

  # 郵便番号から住所を検索
  #
  # @param params [Hash] パラメータ
  # @option params [String] :postal_code 郵便番号（ハイフン付き/なし両方対応）
  # @return [Hash] 検索結果
  #   - message [String, nil] エラーメッセージ（エラー時）
  #   - results [Array<Hash>, nil] 検索結果の配列（成功時）
  #   - status [Integer] HTTPステータスコード
  #   - uri [URI] リクエストURI（デバッグ用）
  #
  # @example 成功時のレスポンス
  #   {
  #     "message" => nil,
  #     "results" => [
  #       {
  #         "address1" => "茨城県",
  #         "address2" => "龍ケ崎市",
  #         "address3" => "古城",
  #         "kana1" => "ｲﾊﾞﾗｷｹﾝ",
  #         "kana2" => "ﾘｭｳｶﾞｻｷｼ",
  #         "kana3" => "ｺｼﾞｮｳ",
  #         "prefcode" => "8",
  #         "zipcode" => "3010834"
  #       }
  #     ],
  #     "status" => 200,
  #     "uri" => #<URI::HTTPS>
  #   }
  #
  # @example エラー時のレスポンス
  #   {
  #     "message" => "パラメータ「郵便番号」の桁数が不正です。",
  #     "results" => [],
  #     "status" => 400,
  #     "uri" => #<URI::HTTPS>
  #   }
  def self.search(params)
    # 郵便番号からハイフンを除去して正規化
    postal_code = params[:postal_code].to_s.gsub('-', '')

    uri = URI("#{API_ENDPOINT}?zipcode=#{postal_code}")

    begin
      # タイムアウト設定付きでHTTPリクエスト
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                  open_timeout: TIMEOUT_SECONDS,
                                  read_timeout: TIMEOUT_SECONDS) do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error("PostalCodeService: タイムアウトエラー - #{e.message}")
      raise StandardError, '郵便番号検索APIのリクエストがタイムアウトしました'
    rescue StandardError => e
      Rails.logger.error("PostalCodeService: APIエラー - #{e.message}")
      raise StandardError, '郵便番号検索APIのリクエストに失敗しました'
    end

    begin
      data = JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.error("PostalCodeService: JSONパースエラー - #{e.message}")
      raise StandardError, '郵便番号検索APIのレスポンスが不正です'
    end

    results = data['results']
    status = data['status']

    # Zipcloud APIは検索結果が0件の時、resultsをnilで返す
    # 一貫性のため、空の配列に正規化
    if status == 200 && results.nil?
      results = []
    end

    {
      'message' => data['message'],
      'results' => results,
      'status' => status,
      'uri' => uri
    }
  end
end
