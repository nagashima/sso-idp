# 住所入力仕様（自動/手動モード）

**作成日**: 2025-11-12
**参考元**: 産後ケアRP実装・実データ

---

## 概要

住所入力には「自動入力モード」と「手動入力モード」の2つがあり、`*_is_address_selected_manually`フラグで管理する。

---

## 自動入力モード（推奨・デフォルト）

### フラグ値
- `home_is_address_selected_manually = 0`
- `workplace_is_address_selected_manually = 0`

### 入力フロー
1. ユーザーが郵便番号を入力（例: `1140023`）
2. Zipcloud APIで検索
3. APIレスポンス:
   ```json
   {
     "address1": "東京都",       // 都道府県名
     "address2": "北区",          // 市区町村名
     "address3": "滝野川",        // 町域
     "prefcode": "13"            // 都道府県コード
   }
   ```
4. `CityService.compare`で市区町村マスタと照合
5. 自動設定:
   - `prefecture_code = 13`（都道府県コード）
   - `master_city_id = 131172`（市区町村マスタID）
   - `address_town = "滝野川"`（町域）
6. 画面表示: `"東京都北区滝野川"` = 都道府県名 + 市区町村名 + 町域
7. ユーザーが番地以降を入力: `address_later = "7"`

### 保存データ例
```ruby
{
  home_is_address_selected_manually: 0,
  home_postal_code: "1140023",
  home_prefecture_code: 13,
  home_master_city_id: 131172,
  home_address_town: "滝野川",
  home_address_later: "7"
}
```

### 画面構成
- 郵便番号入力フィールド
- 都道府県・市区町村（readonly、自動表示）
- 番地以降入力フィールド
- 「都道府県から選択」ボタン（手動モードへ切替）

---

## 手動入力モード

### フラグ値
- `home_is_address_selected_manually = 1`
- `workplace_is_address_selected_manually = 1`

### 入力フロー
1. ユーザーが「都道府県から選択」ボタンをクリック
2. 都道府県プルダウンで選択
3. 市区町村プルダウンで選択（都道府県に紐づく市区町村を動的取得）
4. 番地以降を**すべて**`address_later`に入力（町域も含む）

### 保存データ例
```ruby
{
  home_is_address_selected_manually: 1,
  home_postal_code: nil,  # または空文字
  home_prefecture_code: 13,
  home_master_city_id: 131172,
  home_address_town: nil,  # 手動入力時は空
  home_address_later: "滝野川7-22-3 あずかるコーポ101号室"  # 町域以降すべて
}
```

### 画面構成
- 郵便番号入力フィールド（無効化または非表示）
- 都道府県セレクトボックス
- 市区町村セレクトボックス（都道府県選択後に動的更新）
- 番地以降入力フィールド
- 「郵便番号を自動入力しなおす」ボタン（自動モードへ切替）

---

## モード切替

### 自動 → 手動
- 「都道府県から選択」ボタンクリック
- `is_address_selected_manually = 1`に変更
- 郵便番号フィールドの値をクリア
- `address_town`をクリア
- 都道府県・市区町村セレクトボックスを表示

### 手動 → 自動
- 「郵便番号を自動入力しなおす」ボタンクリック
- `is_address_selected_manually = 0`に変更
- 都道府県・市区町村セレクトボックスを非表示
- 郵便番号フィールドを表示
- 入力済みデータをクリア

---

## カラム定義

### 自宅住所
| カラム名 | 型 | NULL | 説明 |
|---------|-----|------|------|
| `home_is_address_selected_manually` | tinyint unsigned | FALSE | 0: 自動入力, 1: 手動入力 |
| `home_postal_code` | varchar(255) | TRUE | 郵便番号 |
| `home_prefecture_code` | int(11) | TRUE | 都道府県コード |
| `home_master_city_id` | bigint(20) | TRUE | 市区町村マスタID |
| `home_address_town` | varchar(255) | TRUE | 町域（自動入力時のみ） |
| `home_address_later` | varchar(255) | TRUE | 番地以降 |
| `home_latitude` | double | TRUE | 緯度（自動算出） |
| `home_longitude` | double | TRUE | 経度（自動算出） |

### 勤務先住所
| カラム名 | 型 | NULL | 説明 |
|---------|-----|------|------|
| `workplace_is_address_selected_manually` | tinyint unsigned | TRUE | 0: 自動入力, 1: 手動入力 |
| `workplace_postal_code` | varchar(255) | TRUE | 郵便番号 |
| `workplace_prefecture_code` | int(11) | TRUE | 都道府県コード |
| `workplace_master_city_id` | bigint(20) | TRUE | 市区町村マスタID |
| `workplace_address_town` | varchar(255) | TRUE | 町域（自動入力時のみ） |
| `workplace_address_later` | varchar(255) | TRUE | 番地以降 |

※ 勤務先には緯度経度なし

---

## 緯度経度の算出

### 算出タイミング
- User作成時に`UserService.create_from_signup`内で自動算出
- `AddressService.coordinates`を使用

### 算出ロジック
```ruby
# 自動入力の場合
coordinates = AddressService.coordinates(
  home_master_city_id,
  home_address_town  # "滝野川"
)
# → "東京都北区滝野川"で緯度経度を取得

# 手動入力の場合
coordinates = AddressService.coordinates(
  home_master_city_id,
  ''  # address_townは空
)
# → "東京都北区"で緯度経度を取得
```

### データ例
```ruby
{
  home_latitude: 35.744941,
  home_longitude: 139.72433
}
```

---

## UI/UXのポイント

### 自動入力モード（推奨）
- ✅ 郵便番号だけで住所が自動入力される（ユーザー負担小）
- ✅ 町域まで正確に入力される
- ✅ 緯度経度がより正確

### 手動入力モード
- ⚠️ 郵便番号で見つからない場合の代替手段
- ⚠️ 町域が`address_later`に含まれるため、データ構造が異なる
- ⚠️ 緯度経度の精度が市区町村レベルに低下

### エラーハンドリング
1. **郵便番号が見つからない**: エラーメッセージ表示 + 手動入力モードへの誘導
2. **市区町村マスタと不一致**: `CityService.compare`で`masterCity: nil`になる → エラー表示
3. **Zipcloud API障害**: タイムアウト → 手動入力モードへフォールバック

---

## 参考資料

- 産後ケアRP実装: `/Users/n/Workspace/2049/postnatal-care`
- Figma画像: `/Users/n/Workspace/Labo/work/sso-idp/tmp/user_address_input01.png`, `user_address_input02.png`
- 実データサンプル: `home_postal_code=1140023, home_master_city_id=131172, home_address_town="滝野川"`
