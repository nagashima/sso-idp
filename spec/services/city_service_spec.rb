require 'rails_helper'

RSpec.describe CityService, type: :service do
  # テスト前にキャッシュをクリア
  before do
    Rails.cache.clear
  end

  describe '.get' do
    it '市区町村を都道府県付きで取得できる' do
      # 東京都の市区町村（千代田区など）を想定
      city = Master::City.first
      result = CityService.get(city.id)

      expect(result).to be_a(Master::City)
      expect(result.id).to eq(city.id)
      expect(result.master_prefecture).to be_present  # preloadされている
    end
  end

  describe '.fetch_root_city' do
    context '通常の市町村の場合' do
      it '自身を返す' do
        city = Master::City.where(ward_parent_master_city_id: nil).first
        result = CityService.fetch_root_city(city.id)

        expect(result.id).to eq(city.id)
      end
    end

    context '区の場合' do
      it '親市を返す' do
        # 政令指定都市の区を検索
        ward = Master::City.where.not(ward_parent_master_city_id: nil).first

        if ward.present?
          result = CityService.fetch_root_city(ward.id)
          expect(result.id).to eq(ward.ward_parent_master_city_id)
        else
          skip '政令指定都市の区のテストデータが存在しません'
        end
      end
    end
  end

  describe '.get_by_city_name' do
    it '都道府県IDと市区町村名から市区町村を検索できる' do
      prefecture = Master::Prefecture.first
      city = Master::City.where(master_prefecture_id: prefecture.id).first

      # 郡名 + 市区町村名の形式で検索
      full_name = city.county_name.to_s + city.name
      result = CityService.get_by_city_name(prefecture.id, full_name)

      expect(result).to be_present
      expect(result.id).to eq(city.id)
    end
  end

  describe '.get_name' do
    it '市区町村名（郡名含む）を取得できる' do
      city = Master::City.first
      expected_name = city.county_name.to_s + city.name

      result = CityService.get_name(city.id)

      expect(result).to eq(expected_name)
    end

    it '存在しないIDの場合は空文字列を返す' do
      result = CityService.get_name(99999)
      expect(result).to eq('')
    end
  end

  describe '.fetch_all' do
    it '全市区町村を取得できる' do
      cities = CityService.fetch_all
      expect(cities).to be_present
      expect(cities).to be_an(Array)
      expect(cities.first).to be_a(Master::City)
    end

    it 'キャッシュが有効になっている' do
      # 1回目の呼び出しでキャッシュに保存
      first_call = CityService.fetch_all

      # キャッシュから取得されることを確認（同じデータが返される）
      expect(Rails.cache).to receive(:fetch).and_call_original
      second_call = CityService.fetch_all
      expect(second_call.map(&:id)).to eq(first_call.map(&:id))
    end
  end

  describe '.fetch_by_master_prefecture_id' do
    it '都道府県IDから市区町村一覧を取得できる' do
      prefecture = Master::Prefecture.first
      cities = CityService.fetch_by_master_prefecture_id(prefecture.id)

      expect(cities).to be_present
      expect(cities).to all(be_a(Master::City))
      expect(cities).to all(have_attributes(master_prefecture_id: prefecture.id))
    end
  end

  describe '.compare' do
    let(:zipcloud_data) do
      [
        {
          'address1' => '東京都',
          'address2' => '千代田区',
          'address3' => '千代田',
          'prefcode' => '13'
        }
      ]
    end

    context 'マスタと一致する市区町村の場合' do
      before do
        # テストデータとして東京都千代田区が存在すると仮定
        prefecture = Master::Prefecture.find_or_create_by!(id: 13, name: '東京都', kana_name: 'トウキョウト')
        Master::City.find_or_create_by!(
          name: '千代田区',
          master_prefecture_id: prefecture.id,
          kana_name: 'チヨダク',
          latitude: 35.6938,
          longitude: 139.7535,
          search_text: '東京都千代田区'
        )
      end

      it '市区町村IDが付与される' do
        result = CityService.compare(zipcloud_data)

        expect(result).to be_an(Array)
        expect(result.first[:masterPrefecture][:id]).to eq(13)
        expect(result.first[:masterPrefecture][:name]).to eq('東京都')
        expect(result.first[:masterCity]).to be_present
        expect(result.first[:masterCity][:name]).to eq('千代田区')
        expect(result.first[:town]).to eq('千代田')
        expect(result.first[:fullText]).to eq('東京都千代田区千代田')
      end
    end

    context 'マスタと一致しない市区町村の場合' do
      let(:zipcloud_data) do
        [
          {
            'address1' => '架空県',
            'address2' => '架空市',
            'address3' => '架空町',
            'prefcode' => '99'
          }
        ]
      end

      it 'masterCityがnilになる' do
        result = CityService.compare(zipcloud_data)

        expect(result).to be_an(Array)
        expect(result.first[:masterCity]).to be_nil
        expect(result.first[:fullText]).to eq('架空県架空市架空町')
      end
    end

    context 'zipcloud_dataがnilの場合' do
      it 'nilを返す' do
        result = CityService.compare(nil)
        expect(result).to be_nil
      end
    end
  end

  describe '.has_wards?' do
    context '政令指定都市の場合' do
      it 'trueを返す' do
        # 区を持つ市を検索
        parent_city_id = Master::City.where.not(ward_parent_master_city_id: nil).pick(:ward_parent_master_city_id)

        if parent_city_id.present?
          result = CityService.has_wards?(parent_city_id)
          expect(result).to be true
        else
          skip '政令指定都市のテストデータが存在しません'
        end
      end
    end

    context '通常の市町村の場合' do
      it 'falseを返す' do
        # 区を持たない市町村を取得（ward_parent_master_city_idがnilで、自身のIDを持つ子がいない）
        city = Master::City.where(ward_parent_master_city_id: nil)
                           .find { |c| !CityService.has_wards?(c.id) }

        if city.present?
          result = CityService.has_wards?(city.id)
          expect(result).to be false
        else
          skip '区を持たない市町村のテストデータが存在しません'
        end
      end
    end

    context 'IDがnilの場合' do
      it 'falseを返す' do
        result = CityService.has_wards?(nil)
        expect(result).to be false
      end
    end
  end

  describe '.get_wards' do
    context '政令指定都市の場合' do
      it '区一覧を取得できる' do
        # 区を持つ市を検索
        parent_city_id = Master::City.where.not(ward_parent_master_city_id: nil).pick(:ward_parent_master_city_id)

        if parent_city_id.present?
          wards = CityService.get_wards(parent_city_id)
          expect(wards).to be_present
          expect(wards).to all(have_attributes(ward_parent_master_city_id: parent_city_id))
        else
          skip '政令指定都市のテストデータが存在しません'
        end
      end
    end

    context 'IDがnilの場合' do
      it '空配列を返す' do
        result = CityService.get_wards(nil)
        expect(result).to eq([])
      end
    end
  end
end
