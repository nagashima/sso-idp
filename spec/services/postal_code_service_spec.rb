require 'rails_helper'

RSpec.describe PostalCodeService, type: :service do
  describe '.search' do
    let(:postal_code) { '1000001' }
    let(:api_url) { "https://zipcloud.ibsnet.co.jp/api/search?zipcode=#{postal_code}" }

    context '正常な郵便番号で検索した場合' do
      let(:success_response) do
        {
          'message' => nil,
          'results' => [
            {
              'address1' => '東京都',
              'address2' => '千代田区',
              'address3' => '千代田',
              'kana1' => 'ﾄｳｷｮｳﾄ',
              'kana2' => 'ﾁﾖﾀﾞｸ',
              'kana3' => 'ﾁﾖﾀﾞ',
              'prefcode' => '13',
              'zipcode' => '1000001'
            }
          ],
          'status' => 200
        }.to_json
      end

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })
      end

      it '住所情報を取得できる' do
        result = PostalCodeService.search(postal_code: postal_code)

        expect(result['status']).to eq(200)
        expect(result['results']).to be_an(Array)
        expect(result['results'].first['address1']).to eq('東京都')
        expect(result['results'].first['address2']).to eq('千代田区')
      end
    end

    context 'ハイフン付き郵便番号で検索した場合' do
      let(:postal_code_with_hyphen) { '100-0001' }
      let(:normalized_api_url) { 'https://zipcloud.ibsnet.co.jp/api/search?zipcode=1000001' }

      let(:success_response) do
        {
          'message' => nil,
          'results' => [{ 'address1' => '東京都', 'address2' => '千代田区', 'address3' => '千代田', 'prefcode' => '13', 'zipcode' => '1000001' }],
          'status' => 200
        }.to_json
      end

      before do
        stub_request(:get, normalized_api_url)
          .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })
      end

      it 'ハイフンを除去して検索できる' do
        result = PostalCodeService.search(postal_code: postal_code_with_hyphen)

        expect(result['status']).to eq(200)
        expect(result['results']).to be_present
      end
    end

    context '検索結果が0件の場合' do
      let(:no_result_response) do
        {
          'message' => nil,
          'results' => nil,  # Zipcloud APIは結果なしの場合nilを返す
          'status' => 200
        }.to_json
      end

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: no_result_response, headers: { 'Content-Type' => 'application/json' })
      end

      it '空の配列に正規化される' do
        result = PostalCodeService.search(postal_code: postal_code)

        expect(result['status']).to eq(200)
        expect(result['results']).to eq([])  # nilではなく空配列
      end
    end

    context '不正な郵便番号の場合' do
      let(:error_response) do
        {
          'message' => 'パラメータ「郵便番号」の桁数が不正です。',
          'results' => nil,
          'status' => 400
        }.to_json
      end

      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: error_response, headers: { 'Content-Type' => 'application/json' })
      end

      it 'エラーメッセージを含む結果を返す' do
        result = PostalCodeService.search(postal_code: postal_code)

        expect(result['status']).to eq(400)
        expect(result['message']).to be_present
      end
    end

    context 'APIがタイムアウトした場合' do
      before do
        stub_request(:get, api_url).to_timeout
      end

      it 'StandardErrorを発生させる' do
        expect {
          PostalCodeService.search(postal_code: postal_code)
        }.to raise_error(StandardError, /タイムアウト/)
      end
    end

    context 'API接続エラーが発生した場合' do
      before do
        stub_request(:get, api_url).to_raise(SocketError)
      end

      it 'StandardErrorを発生させる' do
        expect {
          PostalCodeService.search(postal_code: postal_code)
        }.to raise_error(StandardError, /リクエストに失敗/)
      end
    end

    context '不正なJSONレスポンスの場合' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: 'invalid json', headers: { 'Content-Type' => 'application/json' })
      end

      it 'StandardErrorを発生させる' do
        expect {
          PostalCodeService.search(postal_code: postal_code)
        }.to raise_error(StandardError, /レスポンスが不正/)
      end
    end
  end
end
