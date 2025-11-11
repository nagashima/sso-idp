require 'rails_helper'

RSpec.describe AddressService, type: :service do
  describe '.coordinates' do
    let(:prefecture) { Master::Prefecture.first }
    let(:city) { Master::City.where(master_prefecture_id: prefecture.id).first }
    let(:address) { '1-2-3' }

    context '正常に緯度経度が取得できる場合' do
      before do
        # Geocoderのモック設定
        allow(Geocoder).to receive(:coordinates).and_return([35.123456, 139.123456])
      end

      it '緯度経度を返す' do
        result = AddressService.coordinates(city.id, address)

        expect(result[:latitude]).to eq(35.123456)
        expect(result[:longitude]).to eq(139.123456)
      end

      it '都道府県名+市区町村名+郡名+住所でGeocoderを呼び出す' do
        expected_address = city.master_prefecture.name + city.name
        expected_address += city.county_name if city.county_name.present?
        expected_address += address

        expect(Geocoder).to receive(:coordinates).with(expected_address)
        AddressService.coordinates(city.id, address)
      end
    end

    context '市区町村が存在しない場合' do
      it 'latitude, longitudeともnilを返す' do
        result = AddressService.coordinates(99999, address)

        expect(result[:latitude]).to be_nil
        expect(result[:longitude]).to be_nil
      end
    end

    context '市区町村IDがnilの場合' do
      it 'latitude, longitudeともnilを返す' do
        result = AddressService.coordinates(nil, address)

        expect(result[:latitude]).to be_nil
        expect(result[:longitude]).to be_nil
      end
    end

    context 'Geocoderがエラーを返した場合' do
      before do
        allow(Geocoder).to receive(:coordinates).and_raise(StandardError.new('API Error'))
        # ログ出力をモック（エラーログが出力されることを確認）
        allow(Rails.logger).to receive(:error)
      end

      it 'latitude, longitudeともnilを返す' do
        result = AddressService.coordinates(city.id, address)

        expect(result[:latitude]).to be_nil
        expect(result[:longitude]).to be_nil
      end

      it 'エラーログを出力する' do
        expect(Rails.logger).to receive(:error).with(/AddressService: Geocoderエラー/)
        AddressService.coordinates(city.id, address)
      end
    end

    context '住所が空の場合' do
      before do
        allow(Geocoder).to receive(:coordinates).and_return([35.123456, 139.123456])
      end

      it '市区町村名までで検索する' do
        expected_address = city.master_prefecture.name + city.name
        expected_address += city.county_name if city.county_name.present?

        expect(Geocoder).to receive(:coordinates).with(expected_address)
        AddressService.coordinates(city.id, '')
      end
    end
  end

  describe '.pref_city_town' do
    let(:prefecture) { Master::Prefecture.first }
    let(:city) { Master::City.where(master_prefecture_id: prefecture.id).first }
    let(:town) { '千代田' }

    before do
      # PrefectureService, CityServiceのモック
      allow(PrefectureService).to receive(:get_name).with(prefecture.id).and_return(prefecture.name)
      allow(CityService).to receive(:get_name).with(city.id).and_return(city.name)
    end

    it '都道府県名+市区町村名+町名を結合した文字列を返す' do
      result = AddressService.pref_city_town(prefecture.id, city.id, town)

      expect(result).to eq("#{prefecture.name}#{city.name}#{town}")
    end

    context '町名が空の場合' do
      it '都道府県名+市区町村名のみを返す' do
        result = AddressService.pref_city_town(prefecture.id, city.id, '')

        expect(result).to eq("#{prefecture.name}#{city.name}")
      end
    end

    context '町名がnilの場合' do
      it '都道府県名+市区町村名のみを返す' do
        result = AddressService.pref_city_town(prefecture.id, city.id, nil)

        expect(result).to eq("#{prefecture.name}#{city.name}")
      end
    end
  end
end
