# 都道府県マスタ関連の処理を提供するサービス
#
# 主な機能:
# - 都道府県の取得（キャッシュ付き）
# - ID指定での都道府県取得
# - 都道府県名の取得
class PrefectureService
  # 全都道府県を取得（キャッシュ付き）
  #
  # @return [ActiveRecord::Relation<Master::Prefecture>] 全都道府県
  def self.all
    Rails.cache.fetch('prefectures_all', expires_in: 7.days) do
      Master::Prefecture.all.to_a
    end
  end

  # 指定したIDの都道府県を取得
  #
  # @param master_prefecture_id [Integer] 都道府県ID
  # @return [Master::Prefecture, nil] 都道府県オブジェクト
  def self.get(master_prefecture_id)
    prefectures = all.select { |prefecture| prefecture.id == master_prefecture_id }
    prefectures.first
  end

  # 指定したIDの都道府県名を取得
  #
  # @param master_prefecture_id [Integer] 都道府県ID
  # @return [String] 都道府県名（見つからない場合は空文字列）
  def self.get_name(master_prefecture_id)
    prefecture = get(master_prefecture_id)
    prefecture.present? ? prefecture.name : ''
  end
end
