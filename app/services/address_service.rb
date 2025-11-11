# 住所関連の処理を提供するサービス
#
# 主な機能:
# - 住所から緯度経度を算出（Geocoder使用）
# - 都道府県・市区町村・町名を結合した文字列の生成
class AddressService
  # 市区町村IDと町名から緯度経度を算出
  #
  # Geocoder gemを使用して、住所文字列から緯度経度を取得します。
  # ユーザーは緯度経度を意識せず、住所入力だけで自動算出されます。
  #
  # @param city_id [Integer] 市区町村ID
  # @param address [String] 町名以降の住所（例: "古城1-2-3"）
  # @return [Hash] 緯度経度のハッシュ
  #   - latitude [Float, nil] 緯度（取得失敗時はnil）
  #   - longitude [Float, nil] 経度（取得失敗時はnil）
  #
  # @example
  #   AddressService.coordinates(123, "古城1-2-3")
  #   # => { latitude: 35.123456, longitude: 139.123456 }
  def self.coordinates(city_id, address = '')
    latitude = nil
    longitude = nil

    city = city_id ? Master::City.preload(:master_prefecture).find_by(id: city_id) : nil

    if city.present?
      # 検索用住所文字列を構築
      # 例: 「茨城県龍ケ崎市古城1-2-3」
      search_address = city.master_prefecture.name + city.name
      search_address += city.county_name if city.county_name.present?
      search_address += address.to_s

      begin
        # Geocoder gemで緯度経度を取得
        latitude, longitude = Geocoder.coordinates(search_address)
      rescue StandardError => e
        Rails.logger.error("AddressService: Geocoderエラー - #{e.message}")
        # エラー時はnilを返す（ユーザーには影響させない）
      end
    end

    { latitude: latitude, longitude: longitude }
  end

  # 都道府県・市区町村・町名を結合した文字列を生成
  #
  # 画面表示用に「都道府県名 + 市区町村名 + 町名」を結合した文字列を返します。
  #
  # @param master_prefecture_id [Integer] 都道府県ID
  # @param master_city_id [Integer] 市区町村ID
  # @param town [String] 町名
  # @return [String] 結合された住所文字列
  #
  # @example
  #   AddressService.pref_city_town(8, 123, "古城")
  #   # => "茨城県龍ケ崎市古城"
  def self.pref_city_town(master_prefecture_id, master_city_id, town)
    PrefectureService.get_name(master_prefecture_id) +
      CityService.get_name(master_city_id) +
      town.to_s
  end
end
