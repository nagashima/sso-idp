require 'rails_helper'

RSpec.describe PrefectureService, type: :service do
  # テスト前にキャッシュをクリア
  before do
    Rails.cache.clear
  end

  describe '.all' do
    it '全都道府県を取得できる' do
      prefectures = PrefectureService.all
      expect(prefectures).to be_present
      expect(prefectures).to be_an(Array)
      expect(prefectures.first).to be_a(Master::Prefecture)
    end

    it 'キャッシュが有効になっている' do
      # 1回目の呼び出しでキャッシュに保存
      first_call = PrefectureService.all

      # キャッシュから取得されることを確認（同じデータが返される）
      expect(Rails.cache).to receive(:fetch).and_call_original
      second_call = PrefectureService.all
      expect(second_call.map(&:id)).to eq(first_call.map(&:id))
    end
  end

  describe '.get' do
    context '存在する都道府県IDを指定した場合' do
      it '都道府県オブジェクトを取得できる' do
        # 東京都（ID: 13）を想定
        prefecture = PrefectureService.get(13)
        expect(prefecture).to be_present
        expect(prefecture).to be_a(Master::Prefecture)
        expect(prefecture.id).to eq(13)
      end
    end

    context '存在しない都道府県IDを指定した場合' do
      it 'nilを返す' do
        prefecture = PrefectureService.get(99999)
        expect(prefecture).to be_nil
      end
    end
  end

  describe '.get_name' do
    context '存在する都道府県IDを指定した場合' do
      it '都道府県名を取得できる' do
        # 東京都（ID: 13）を想定
        name = PrefectureService.get_name(13)
        expect(name).to eq('東京都')
      end
    end

    context '存在しない都道府県IDを指定した場合' do
      it '空文字列を返す' do
        name = PrefectureService.get_name(99999)
        expect(name).to eq('')
      end
    end
  end
end
