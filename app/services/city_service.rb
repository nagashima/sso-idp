# 市区町村マスタ関連の処理を提供するサービス
#
# 主な機能:
# - 市区町村の取得（キャッシュ付き）
# - 都道府県IDから市区町村一覧取得
# - 郵便番号検索結果とマスタの照合
# - 政令指定都市の区の扱い
class CityService
  # 指定したIDの市区町村を取得（都道府県も含めてpreload）
  #
  # @param city_id [Integer] 市区町村ID
  # @return [Master::City] 市区町村オブジェクト
  def self.get(city_id)
    Master::City.preload(:master_prefecture).find(city_id)
  end

  # 市区町村の親市を取得（政令指定都市の区の場合）
  #
  # 例: 「札幌市中央区」の場合、「札幌市」を返す
  #     通常の市町村の場合、自身を返す
  #
  # @param city_id [Integer] 市区町村ID
  # @return [Master::City] 親市または自身
  def self.fetch_root_city(city_id)
    city = get(city_id)
    city.ward_parent_master_city_id.present? ? get(city.ward_parent_master_city_id) : city
  end

  # 都道府県IDと市区町村名から市区町村を検索
  #
  # county_name（郡名）とnameを結合した名前で検索
  # 例: 「龍ケ崎市」「札幌市中央区」など
  #
  # @param prefecture_id [Integer] 都道府県ID
  # @param city_name [String] 市区町村名
  # @return [Master::City, nil] 市区町村オブジェクト
  def self.get_by_city_name(prefecture_id, city_name)
    Master::City.preload(:master_prefecture)
                .where('CONCAT(COALESCE(county_name, ""), name) = ?', city_name)
                .find_by(master_prefecture_id: prefecture_id)
  end

  # 指定したIDの市区町村名を取得（郡名も含む）
  #
  # @param city_id [Integer] 市区町村ID
  # @param _master_prefecture_id [Integer, nil] 都道府県ID（未使用、互換性のため残存）
  # @return [String] 市区町村名（郡名 + 市区町村名）
  def self.get_name(city_id, _master_prefecture_id = nil)
    cities = fetch_all
    cities.each do |city|
      return city.county_name.to_s + city.name if city_id == city.id
    end
    ''
  end

  # 全市区町村を取得（キャッシュ付き）
  #
  # @return [Array<Master::City>] 全市区町村
  def self.fetch_all
    Rails.cache.fetch('cities_all', expires_in: 7.days) do
      Master::City.all.to_a
    end
  end

  # 指定した都道府県IDに属する市区町村一覧を取得
  #
  # @param master_prefecture_id [Integer] 都道府県ID
  # @return [ActiveRecord::Relation<Master::City>] 市区町村一覧
  def self.fetch_by_master_prefecture_id(master_prefecture_id)
    Master::City.where(master_prefecture_id: master_prefecture_id)
  end

  # 郵便番号検索APIの結果とマスタテーブルを照合
  #
  # PostalCodeService.searchの結果を受け取り、
  # 市区町村マスタと照合してIDを付与した結果を返す
  #
  # @param zipcloud_data [Array<Hash>] PostalCodeService.search結果のresults配列
  # @return [Array<Hash>] 照合結果
  #
  # @example 戻り値の例
  #   [
  #     {
  #       masterPrefecture: { id: 8, name: "茨城県" },
  #       masterCity: { id: 123, name: "龍ケ崎市" },
  #       town: "古城",
  #       fullText: "茨城県龍ケ崎市古城"
  #     }
  #   ]
  def self.compare(zipcloud_data)
    results = zipcloud_data&.map do |result|
      master_prefecture_id = result['prefcode'].to_i

      # Zipcloud APIの市区町村名（address2）とマスタの照合
      # county_name（郡名）+ name で完全一致検索
      master_city_id = Master::City.select('id')
                                    .where('CONCAT(IFNULL(`county_name`, ""), `name`) = :full_name',
                                           full_name: result['address2'])
                                    .where(master_prefecture_id: master_prefecture_id)
                                    .pick('id')

      master_city = master_city_id ? Master::City.preload(:master_prefecture).find(master_city_id) : nil

      {
        masterPrefecture: {
          id: master_prefecture_id,
          name: result['address1']
        },
        masterCity: if master_city
                      {
                        id: master_city.id,
                        name: master_city.name
                      }
                    end,
        town: result['address3'],
        fullText: result['address1'] + result['address2'] + result['address3']
      }
    end

    results
  end

  # 指定した市IDが政令指定都市（区を持つ市）かどうかを判定
  #
  # @param master_city_id [Integer] 市区町村ID
  # @return [Boolean] 区を持つ市の場合true
  def self.has_wards?(master_city_id)
    return false if master_city_id.blank?

    Master::City.where(ward_parent_master_city_id: master_city_id).exists?
  end

  # 指定した市ID配下の区一覧を取得
  #
  # @param master_city_id [Integer] 親市のID
  # @return [ActiveRecord::Relation<Master::City>] 区の一覧
  def self.get_wards(master_city_id)
    return [] if master_city_id.blank?

    Master::City.where(ward_parent_master_city_id: master_city_id).order(:id)
  end
end
