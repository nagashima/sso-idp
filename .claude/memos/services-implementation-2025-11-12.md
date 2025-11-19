# Services層実装メモ（住所・郵便番号関連）

**日時**: 2025-11-12
**ブランチ**: `feature/user-schema-refactor`
**目的**: Phase 3（会員登録フォーム本番対応）の準備として、住所・郵便番号関連のServices層を実装

---

## 実装したサービス

### 1. PrefectureService
**ファイル**: `app/services/prefecture_service.rb`

**機能**:
- 全都道府県取得（キャッシュ付き、7日間）
- ID指定での都道府県取得
- 都道府県名の取得

**主要メソッド**:
- `all` - 全都道府県をキャッシュから取得
- `get(master_prefecture_id)` - ID指定で都道府県取得
- `get_name(master_prefecture_id)` - 都道府県名を取得

**参考元**: `/Users/n/Workspace/2049/postnatal-care/app/services/prefecture_service.rb`

**差分**:
- `available_cities`, `formatted_available_cities` は省略（RP固有の契約管理機能）
- キャッシュキー名を `prefecture_all` → `prefectures_all` に変更（複数形）

---

### 2. PostalCodeService
**ファイル**: `app/services/postal_code_service.rb`

**機能**:
- 郵便番号から住所を検索（Zipcloud API使用）
- ハイフン付き郵便番号の正規化
- タイムアウト・エラーハンドリング

**主要メソッド**:
- `search(params)` - 郵便番号検索（`:postal_code` パラメータ）

**API仕様**:
- エンドポイント: `https://zipcloud.ibsnet.co.jp/api/search`
- タイムアウト: 5秒
- レスポンス: JSON形式
  ```ruby
  {
    "message" => nil,
    "results" => [
      {
        "address1" => "茨城県",
        "address2" => "龍ケ崎市",
        "address3" => "古城",
        "kana1" => "ｲﾊﾞﾗｷｹﾝ",
        "kana2" => "ﾘｭｳｶﾞｻｷｼ",
        "kana3" => "ｺｼﾞｮｳ",
        "prefcode" => "8",
        "zipcode" => "3010834"
      }
    ],
    "status" => 200
  }
  ```

**参考元**: `/Users/n/Workspace/2049/postnatal-care/app/services/zipcloud_service.rb`

**差分・改善点**:
- サービス名を `ZipcloudService` → `PostalCodeService` に変更（普遍的な名前）
- タイムアウト設定を追加（`open_timeout`, `read_timeout`）
- ハイフン除去処理を追加（`123-4567` → `1234567`）
- JSON.parseのエラーハンドリング追加
- カスタム例外 `ApiError` ではなく標準の `StandardError` を使用
- ログ出力を追加

**動作検証**:
```bash
docker-compose exec app bundle exec rails runner "puts PostalCodeService.search(postal_code: '100-0001').to_json"
```

**検証結果**: ✅ 成功
```json
{
  "message": null,
  "results": [
    {
      "address1": "東京都",
      "address2": "千代田区",
      "address3": "千代田",
      "prefcode": "13",
      "zipcode": "1000001"
    }
  ],
  "status": 200
}
```

---

### 3. CityService
**ファイル**: `app/services/city_service.rb`

**機能**:
- 市区町村の取得（キャッシュ付き、7日間）
- 都道府県から市区町村一覧取得
- 郵便番号検索結果とマスタの照合
- 政令指定都市の区の扱い

**主要メソッド**:
- `get(city_id)` - ID指定で市区町村取得（都道府県もpreload）
- `fetch_root_city(city_id)` - 区の場合は親市を取得
- `get_by_city_name(prefecture_id, city_name)` - 都道府県ID + 市区町村名で検索
- `get_name(city_id)` - 市区町村名を取得（郡名も含む）
- `fetch_all` - 全市区町村をキャッシュから取得
- `fetch_by_master_prefecture_id(prefecture_id)` - 都道府県IDから市区町村一覧
- `compare(zipcloud_data)` - **重要**: Zipcloud APIの結果とマスタを照合
- `has_wards?(city_id)` - 政令指定都市判定
- `get_wards(city_id)` - 区一覧取得

**照合ロジック（`compare`）**:
- Zipcloud APIの `address2`（市区町村名）とマスタの `CONCAT(county_name, name)` で完全一致
- マッチした場合はマスタIDを付与
- マッチしない場合は `masterCity: nil`

**参考元**: `/Users/n/Workspace/2049/postnatal-care/app/services/city_service.rb`

**差分・省略箇所**:
- `ward_children` - `get_wards`と重複のため省略
- `get_ward_items`, `extract_ward_only` - 現時点で不要なため省略（必要になったら追加）

---

### 4. AddressService
**ファイル**: `app/services/address_service.rb`

**機能**:
- 住所から緯度経度を算出（Geocoder gem使用）
- 都道府県・市区町村・町名の結合文字列生成

**主要メソッド**:
- `coordinates(city_id, address)` - **重要**: 住所から緯度経度を自動算出
- `pref_city_town(prefecture_id, city_id, town)` - 表示用住所文字列生成

**緯度経度算出の仕組み**:
1. 市区町村IDから都道府県名・市区町村名を取得
2. 「都道府県名 + 市区町村名 + 郡名（あれば）+ 町名以降」を結合
3. Geocoder gemに渡して緯度経度を取得
4. エラー時は `{ latitude: nil, longitude: nil }` を返す

**参考元**: `/Users/n/Workspace/2049/postnatal-care/app/services/address_service.rb`

**差分**:
- ほぼそのまま流用
- エラーハンドリングを追加（Geocoder APIエラー時のログ出力）

**動作検証**:
```bash
docker-compose exec app bundle exec rails runner "
city = Master::City.first
result = AddressService.coordinates(city.id, '1-2-3')
puts result.to_json
"
```

**検証結果**: ✅ 成功
```json
{
  "latitude": 43.0519535,
  "longitude": 141.4741041
}
```

---

## 技術的な判断事項

### 1. サービス名の命名規則
**方針**: 技術名ではなく機能・ドメイン名で命名

- `ZipcloudService` → `PostalCodeService`（郵便番号検索サービス）
- `GeocoderService` → `AddressService`（住所関連サービス）

**理由**:
- 将来的にZipcloud APIを別のAPIに切り替える可能性
- Geocoder gemを別のジオコーディングサービスに切り替える可能性
- 呼び出し側のコードを変更せずに実装を差し替え可能

### 2. 政令指定都市の区の扱い
**参考RPの実装を踏襲**:
- 区も通常の市町村も、全て `master_cities` テーブルに格納
- セレクトボックスでは区も市町村と同列に選択
- 区の場合は `ward_parent_master_city_id` に親市のIDが入る

**例**:
- 「札幌市中央区」も「龍ケ崎市」も、どちらも `home_master_city_id` に格納
- 表示名は `county_name + name`（例: 「札幌市中央区」「龍ケ崎市」）

### 3. キャッシュ設定
**統一仕様**:
- 有効期限: 7日間
- キー名: `prefectures_all`, `cities_all`

**参考RPとの違い**:
- 参考RPは `Rails.configuration.app_settings[:cache_days_master].days`
- IdP側は固定値（7日間）で実装
- 将来的に設定ファイル化も検討可能

### 4. エラーハンドリング
**PostalCodeService**:
- タイムアウトエラー → `StandardError` + ログ出力
- JSON.parseエラー → `StandardError` + ログ出力
- ユーザーには「郵便番号検索に失敗しました」的なメッセージ

**AddressService**:
- Geocoderエラー → ログ出力のみ、`{ latitude: nil, longitude: nil }` を返す
- ユーザーには影響させない（緯度経度は裏側の処理）

---

## 依存関係

### Gemfile追加 ✅
```ruby
gem 'geocoder'  # 住所→緯度経度変換
gem 'webmock'   # HTTP request stubbing (test環境)
```

### Initializer設定 ✅
**ファイル**: `config/initializers/geocoder.rb`

```ruby
Geocoder.configure(
  timeout: 5,
  lookup: :google,
  api_key: ENV['GOOGLE_GEOCODING_API_KEY'] ||
           Rails.application.credentials.dig(:google, :server_api_key),
  units: :km,
  cache: Rails.cache,
  cache_options: {
    expiration: 7.days,
    prefix: 'geocoder:'
  }
)
```

### 環境変数

**開発環境（個人用）**: `.env.local` に設定
```
GOOGLE_GEOCODING_API_KEY=your_api_key_here
```

**チーム共有用（推奨）**: `credentials.yml.enc` に設定
```bash
docker-compose exec app bundle exec rails credentials:edit

# 以下を追加
google:
  server_api_key: "チーム取得のAPIキー"
```

**注意**:
- 現在は`.env.local`で個人用APIキーを使用中
- 正式版の開発用APIキーをチームで取得したら、`credentials.yml.enc`に移行推奨
- `config/initializers/geocoder.rb`は環境変数とcredentials両方に対応済み

---

## Unit テスト ✅

### テストファイル（4ファイル、40テスト）

**作成したテスト**:
- `spec/services/prefecture_service_spec.rb` - 7テスト
- `spec/services/postal_code_service_spec.rb` - 8テスト
- `spec/services/city_service_spec.rb` - 16テスト
- `spec/services/address_service_spec.rb` - 9テスト

**テスト結果**: 全40テストがパス ✅

### WebMock設定

`spec/rails_helper.rb` に追加:
```ruby
require 'webmock/rspec'

RSpec.configure do |config|
  # 外部HTTPリクエストを禁止（localhost/127.0.0.1は許可）
  WebMock.disable_net_connect!(allow_localhost: true)
  # ...
end
```

### テスト内容

**PrefectureService**:
- 全都道府県取得
- ID指定取得
- キャッシュ動作確認

**PostalCodeService**:
- 正常な郵便番号検索
- ハイフン付き郵便番号の正規化
- 検索結果0件の処理
- 不正な郵便番号のエラー処理
- APIタイムアウト・接続エラー
- 不正JSONレスポンス

**CityService**:
- 市区町村取得（都道府県preload）
- 親市取得（政令指定都市の区対応）
- 市区町村名検索
- 全市区町村取得とキャッシュ
- 郵便番号検索結果との照合
- 政令指定都市判定
- 区一覧取得

**AddressService**:
- 住所から緯度経度算出
- Geocoderエラーハンドリング
- 都道府県+市区町村+町名の結合

---

## 発生した問題と修正

### 1. Master::Cityモデルの関連付け名不一致

**問題**:
- モデル: `belongs_to :prefecture`
- サービス: `city.master_prefecture.name`

**修正**: `app/models/master/city.rb`
```ruby
# 修正前
belongs_to :prefecture, class_name: 'Master::Prefecture', foreign_key: :master_prefecture_id

# 修正後
belongs_to :master_prefecture, class_name: 'Master::Prefecture', foreign_key: :master_prefecture_id
```

### 2. AddressServiceでのpreload不足

**問題**: `Master::City.find_by(id: city_id)` で関連付けをpreloadしていない

**修正**: `app/services/address_service.rb`
```ruby
# 修正前
city = city_id ? Master::City.find_by(id: city_id) : nil

# 修正後
city = city_id ? Master::City.preload(:master_prefecture).find_by(id: city_id) : nil
```

### 3. キャッシュテストの問題

**問題**: `object_id` 比較はRailsのキャッシュでは不適切（毎回新しいオブジェクトが生成される）

**修正**: IDの配列で比較
```ruby
# 修正前
expect(second_call.object_id).to eq(first_call.object_id)

# 修正後
expect(Rails.cache).to receive(:fetch).and_call_original
expect(second_call.map(&:id)).to eq(first_call.map(&:id))
```

---

## 次のステップ

### ✅ 完了
1. Geocoder gem追加 → 完了
2. Initializer作成 → 完了
3. Unit テスト作成 → 完了（40テスト全てパス）

### 次にやること
1. **変更をコミット** - Services層、テスト、モデル修正をコミット
2. **Phase 3実装開始** - 設計書（`.claude/plans/phase3-signup-form-refactoring.md`）に従って会員登録フォームをリファクタリング

---

## ファイル一覧

**新規作成 - Services**:
- `app/services/prefecture_service.rb`（38行）
- `app/services/postal_code_service.rb`（103行）
- `app/services/city_service.rb`（151行）
- `app/services/address_service.rb`（58行）

**新規作成 - テスト**:
- `spec/services/prefecture_service_spec.rb`（61行）
- `spec/services/postal_code_service_spec.rb`（146行）
- `spec/services/city_service_spec.rb`（210行）
- `spec/services/address_service_spec.rb`（93行）

**新規作成 - 設定**:
- `config/initializers/geocoder.rb`（28行）

**変更**:
- `Gemfile` - geocoder, webmock追加
- `Gemfile.lock` - 依存関係更新
- `app/models/master/city.rb` - 関連付け名を`:master_prefecture`に変更
- `spec/rails_helper.rb` - WebMock設定追加

**合計**: 新規9ファイル、変更4ファイル

---

## 注意点・懸念事項

### Zipcloud API
- 無料サービスのため、障害・レート制限の可能性あり
- エラーハンドリングは実装済み（手動選択モードへのフォールバック）

### Geocoder API
- Google Geocoding APIは有料（無料枠あり）
- API KEY必須
- レート制限に注意（1日2500リクエストまで無料）

### マスタデータ照合
- Zipcloud APIの市区町村名とマスタの不一致に注意
- `CityService.compare`で照合済み
- 完全一致しない場合は `masterCity: nil`

---

## 参考資料

- 参考RP: `/Users/n/Workspace/2049/postnatal-care`
- Phase 3設計書: `.claude/plans/phase3-signup-form-refactoring.md`
- Zipcloud API: https://zipcloud.ibsnet.co.jp/doc/api
- Geocoder gem: https://github.com/alexreisner/geocoder
