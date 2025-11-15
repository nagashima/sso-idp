# RP向けAPI開発ロードマップ

## 概要
RPサイトがIdPのユーザー情報を管理するためのサーバー間通信API

## 技術要件
- **認証**: Basic認証（client_id/client_secret）
- **セキュリティ**: HTTPS必須、IP制限、CORS制限（ブラウザアクセス不可）
- **通信**: サーバー間通信のみ
- **エンドポイント**: `/api/v1/*`

## Phase 1: GET系API実装（優先度: 高）

### 対象エンドポイント
1. **`GET /api/v1/users/{id}`** - ユーザーID指定取得
2. **`GET /api/v1/users`** - ユーザー検索
   - `ids`: ID複数指定（カンマ区切り）
   - `name`: 氏名（漢字）部分一致
   - `kana_name`: 氏名（かな）部分一致
   - `phone_number`: 電話番号完全一致（ハイフン対応）

### 実装内容
- [x] OpenAPI定義完成（`docs/openapi.yaml`）
- [ ] コントローラー実装
  - [ ] `/app/controllers/api/v1/users_controller.rb`
  - [ ] Basic認証実装
  - [ ] IP制限実装
  - [ ] 検索ロジック実装（name, kana_name, phone_number）
- [ ] ルーティング設定（`config/routes.rb`）
- [ ] レスポンスシリアライザ作成
  - [ ] 除外カラム: `encrypted_password`, `mail_authentication_code`, `mail_authentication_expires_at`, `reset_password_token`, `reset_password_sent_at`, `deleted_at`, `current_sign_in_at`
- [ ] エラーハンドリング
  - [ ] 401: 認証失敗
  - [ ] 403: IP制限
  - [ ] 404: ユーザーが存在しない
  - [ ] 400: パラメータ不正

### テスト計画
- [ ] sso-rpプロジェクトからAPI呼び出しテスト
  - [ ] Basic認証の動作確認
  - [ ] 各検索条件のテスト（ids, name, kana_name, phone_number）
  - [ ] IP制限の動作確認
  - [ ] エラーレスポンスの確認

### 必要なセットアップ
- [ ] RelyingPartyモデルに `client_id`, `client_secret`, `allowed_ips` カラム確認
- [ ] IP制限ミドルウェアまたはbefore_action実装
- [ ] 開発環境でのIP制限設定（localhostからのアクセス許可）

## Phase 2: POST系API実装（ユーザー登録・変更）

### 対象エンドポイント（未定義）
1. **`POST /api/v1/users`** - ユーザー新規登録
2. **`PATCH /api/v1/users/{id}`** - ユーザー情報更新
3. **`DELETE /api/v1/users/{id}`** - ユーザー削除（論理削除）

### 想定仕様

#### ユーザー新規登録 (`POST /api/v1/users`)
**リクエスト**:
```json
{
  "last_name": "山田",
  "first_name": "太郎",
  "last_kana_name": "やまだ",
  "first_kana_name": "たろう",
  "email": "user@example.com",
  "birth_date": "1990-01-01",
  "phone_number": "09012345678",
  ...（その他プロフィール情報）
}
```

**レスポンス**:
```json
{
  "id": 123,
  "message": "ユーザーを作成しました"
}
```

**フロー**:
1. RPからユーザー登録API呼び出し
2. IdPでユーザー作成、IDを返却
3. RPは取得したIDで画像登録API呼び出し（Phase 3）

#### ユーザー情報更新 (`PATCH /api/v1/users/{id}`)
**リクエスト**:
```json
{
  "phone_number": "09087654321",
  "home_postal_code": "1000001",
  ...（更新したいフィールドのみ）
}
```

**レスポンス**:
```json
{
  "id": 123,
  "message": "ユーザー情報を更新しました"
}
```

### 実装内容
- [ ] OpenAPI定義作成
- [ ] コントローラー実装
  - [ ] パラメータバリデーション
  - [ ] Form Objectパターン適用
  - [ ] トランザクション処理
- [ ] エラーハンドリング
  - [ ] 422: バリデーションエラー
  - [ ] 409: メールアドレス重複

### テスト計画
- [ ] sso-rpからユーザー登録テスト
- [ ] バリデーションエラーのテスト
- [ ] 重複チェックのテスト

## Phase 3: 画像登録API実装

### 前提条件
- [ ] WEB版の画像保存機能実装完了
- [ ] MinIO連携実装完了
- [ ] 画像リサイズ・最適化機能実装完了

### 対象エンドポイント（未定義）
**`POST /api/v1/users/{id}/profile_image`** - プロフィール画像登録

### 想定仕様

#### プロフィール画像登録
**リクエスト**:
```json
{
  "image_data": "base64_encoded_image_data"
}
```
または multipart/form-data

**レスポンス**:
```json
{
  "id": 123,
  "profile_image_url": "https://idp.example.com/images/users/123.jpg",
  "message": "画像を登録しました"
}
```

### 2ステップフロー
1. **Step 1**: ユーザー登録API → user_id取得
2. **Step 2**: 画像登録API（user_idを使用）

```
RP → IdP: POST /api/v1/users → { id: 123 }
RP → IdP: POST /api/v1/users/123/profile_image → { profile_image_url: "..." }
```

### 実装内容
- [ ] OpenAPI定義作成
- [ ] コントローラー実装
  - [ ] Base64デコード
  - [ ] ファイル形式バリデーション（JPEG, PNG, GIF）
  - [ ] ファイルサイズ制限（例: 5MB以内）
  - [ ] MinIOへのアップロード
  - [ ] `profile_image_data` カラム更新
- [ ] MinIO連携サービス実装
- [ ] エラーハンドリング
  - [ ] 413: ファイルサイズ超過
  - [ ] 415: 未対応の画像形式

### テスト計画
- [ ] 画像アップロードテスト
- [ ] ファイルサイズ制限テスト
- [ ] 画像形式チェックテスト

## Phase 4: 本番環境対応

### セキュリティ強化
- [ ] Rate Limiting実装
- [ ] アクセスログ記録
- [ ] 監視・アラート設定

### ドキュメント整備
- [ ] OpenAPI定義の最終確認
- [ ] RPサイト向け利用ガイド作成
- [ ] エラーコード一覧作成
- [ ] 認証情報（client_id/client_secret）発行フロー確立

## 実装優先順位

### 今すぐ（Phase 1）
1. GET系API実装
2. Basic認証実装
3. IP制限実装
4. sso-rpからのテスト

### 次（Phase 2）
- ユーザー登録・変更API実装

### その後（Phase 3）
- 画像登録API実装（WEB版画像保存機能完了後）

### 最後（Phase 4）
- 本番環境対応・セキュリティ強化

## 関連ファイル
- API定義: `/docs/openapi.yaml`
- コントローラー: `/app/controllers/api/v1/users_controller.rb`（作成予定）
- ルーティング: `/config/routes.rb`
- テストRP: `../sso-rp`

## メモ
- Basic認証のclient_id/client_secretはRelyingPartyテーブルで管理
- IP制限は開発環境ではlocalhostを許可
- 画像登録は2ステップフロー（登録→画像）で実装
- エラーレスポンスはOpenAPI定義に準拠
