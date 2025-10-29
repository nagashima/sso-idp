# OpenAPI自動生成ガイド

**作成日**: 2025-10-28
**対象**: IdP RP Management API

---

## 📋 目次

1. [背景・目的](#背景目的)
2. [ツール比較](#ツール比較)
3. [rspec-openapi 推奨理由](#rspec-openapi-推奨理由)
4. [セットアップ](#セットアップ)
5. [使い方](#使い方)
6. [Ridgepoleとの関係](#ridgepoleとの関係)
7. [運用フロー](#運用フロー)
8. [注意点・制限事項](#注意点制限事項)

---

## 背景・目的

### 現状

- **手動管理**: `docs/openapi.yaml` を手動で編集・更新
- **同期リスク**: Model変更時に仕様書の更新を忘れる可能性

### 自動生成のメリット

- ✅ Model/Controller変更時の同期漏れ防止
- ✅ テストコードが仕様書として機能
- ✅ 常に最新のAPI仕様を保証
- ✅ メンテナンスコスト削減

---

## ツール比較

### 主要なOpenAPI生成ツール

| ツール | コマンド | 記述方法 | 学習コスト | 推奨度 |
|-------|---------|---------|-----------|-------|
| **rspec-openapi** | `OPENAPI=1 bundle exec rspec` | 通常のRSpec | 低 | ⭐⭐⭐ |
| **rswag** | `rake rswag:specs:swaggerize` | 専用DSL | 中 | ⭐⭐ |
| **apipie-rails** | `rake apipie:static` | アノテーション | 中 | ⭐ |
| **committee** | - | 生成不可（バリデーションのみ） | - | - |

---

## rspec-openapi 推奨理由

### ✅ メリット

#### 1. 既存のRSpecをそのまま活用

```ruby
# 通常のRSpecテスト（特別なDSL不要）
RSpec.describe 'Users API', type: :request do
  it 'returns user' do
    user = create(:user, email: 'test@example.com')
    get "/api/v1/users/#{user.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['email']).to eq('test@example.com')
  end
end

# ↑ これだけでOpenAPI仕様書が生成される
```

#### 2. 学習コスト低い

- 新しいDSLを学ぶ必要なし
- 既存のテストコードから自動生成

#### 3. テストと仕様の一致を保証

```
テスト成功 = 仕様書が正しい
テスト失敗 = 実装が仕様と不一致
```

#### 4. Ridgepoleと完全独立

- schema.rbを読まない
- テスト実行結果から生成
- マイグレーション方式に依存しない

---

### ⚠️ rswagとの比較

| 項目 | rspec-openapi | rswag |
|-----|---------------|-------|
| DSL記述 | ❌ 不要 | ✅ 必要 |
| 既存テスト活用 | ✅ できる | ❌ できない |
| 学習コスト | 低 | 中 |
| 詳細制御 | △ 自動生成ベース | ✅ 細かく制御可能 |
| Swagger UI統合 | 別途必要 | ✅ 組み込み |

**結論**: シンプルさ重視なら **rspec-openapi**

---

## セットアップ

### Step 1: Gemインストール

```bash
# Gemfile に追加
bundle add rspec-openapi --group development,test

# インストール
bundle install
```

---

### Step 2: 設定ファイル

```ruby
# spec/rails_helper.rb

require 'rspec/openapi'

RSpec.configure do |config|
  # OpenAPI出力先
  config.openapi_root = Rails.root.join('docs').to_s

  # OpenAPI仕様書の基本情報
  config.openapi_specs = {
    'openapi.yaml' => {
      openapi: '3.0.3',
      info: {
        title: 'RP Management API',
        version: '1.0.1',
        description: 'RPサイト向けユーザー情報管理API'
      },
      servers: [
        {
          url: 'https://localhost:4443/api/v1',
          description: '開発環境'
        },
        {
          url: 'https://idp.example.com/api/v1',
          description: '本番環境'
        }
      ],
      components: {
        securitySchemes: {
          basicAuth: {
            type: 'http',
            scheme: 'basic'
          }
        }
      },
      security: [
        { basicAuth: [] }
      ]
    }
  }

  # どのテストから生成するか（パスパターン）
  config.openapi_path_records = [
    {
      path_regexp: %r{^/api/v1/},  # /api/v1/ で始まるパスのみ
      spec_path: 'spec/requests/**/*_spec.rb'
    }
  ]
end
```

---

### Step 3: .gitignore（任意）

```bash
# .gitignore

# 自動生成されたOpenAPIファイル（手動管理の場合はコメントアウト）
# docs/openapi.yaml
```

**運用方針**:
- **自動生成運用**: gitignore対象（生成物なので）
- **手動併用**: gitに含める（微調整後コミット）

---

## 使い方

### 基本的な使い方

#### 1. RSpecテスト作成

```ruby
# spec/requests/api/v1/users_spec.rb
require 'rails_helper'

RSpec.describe 'Users API', type: :request do
  let(:client_id) { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  let(:auth_header) do
    credentials = Base64.strict_encode64("#{client_id}:#{client_secret}")
    { 'Authorization' => "Basic #{credentials}" }
  end

  before do
    # RpClient登録（Basic認証用）
    RpClient.create!(
      client_id: client_id,
      client_secret: client_secret,
      name: 'Test Client',
      active: true
    )
  end

  describe 'GET /api/v1/users/:id' do
    it 'returns user by id' do
      user = create(:user, email: 'test@example.com', name: '山田太郎')

      get "/api/v1/users/#{user.id}", headers: auth_header

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'id' => user.id,
        'email' => 'test@example.com',
        'name' => '山田太郎'
      )
    end

    it 'returns 404 when user not found' do
      get '/api/v1/users/99999', headers: auth_header

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/users?email=xxx' do
    it 'returns user by email' do
      user = create(:user, email: 'search@example.com')

      get '/api/v1/users', params: { email: 'search@example.com' }, headers: auth_header

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
      expect(response.parsed_body.first['email']).to eq('search@example.com')
    end

    it 'returns empty array when not found' do
      get '/api/v1/users', params: { email: 'notfound@example.com' }, headers: auth_header

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  describe 'GET /api/v1/users?ids=xxx' do
    it 'returns multiple users' do
      user1 = create(:user, email: 'user1@example.com')
      user2 = create(:user, email: 'user2@example.com')

      get '/api/v1/users', params: { ids: "#{user1.id},#{user2.id}" }, headers: auth_header

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(2)
    end
  end
end
```

---

#### 2. OpenAPI生成

```bash
# 環境変数 OPENAPI=1 でテスト実行
OPENAPI=1 bundle exec rspec spec/requests/api/v1/users_spec.rb

# または全テスト
OPENAPI=1 bundle exec rspec spec/requests
```

**出力**:
```
docs/openapi.yaml が生成される
```

---

#### 3. 生成結果確認

```bash
# Swagger UIで確認
docker run -p 8081:8080 \
  -e SWAGGER_JSON=/openapi.yaml \
  -v $(pwd)/docs/openapi.yaml:/openapi.yaml \
  swaggerapi/swagger-ui

open http://localhost:8081
```

---

### 高度な使い方

#### 1. 特定のテストだけ生成

```ruby
# spec/requests/api/v1/users_spec.rb

# このテストからは生成しない
it 'internal test', openapi: false do
  # ...
end

# このテストから生成する（デフォルト）
it 'returns user' do
  # ...
end
```

---

#### 2. レスポンススキーマのカスタマイズ

```ruby
# spec/rails_helper.rb

RSpec.configure do |config|
  # レスポンススキーマの後処理
  config.after(:each, type: :request) do |example|
    if example.metadata[:openapi]
      # カスタムロジック
    end
  end
end
```

---

## Ridgepoleとの関係

### ✅ 完全に独立して動作

```
┌─────────────────┐
│   Schemafile    │  Ridgepole定義
└────────┬────────┘
         ↓
   ridgepole --apply
         ↓
┌─────────────────┐
│   schema.rb     │  Rails標準形式
└─────────────────┘
         ↑
         │（読まない）
         │
┌─────────────────┐
│  rspec-openapi  │
└────────┬────────┘
         ↓（読む）
┌─────────────────┐
│  RSpecテスト     │  実際のAPI動作
│  + レスポンス    │
└─────────────────┘
```

**重要ポイント**:
- rspec-openapiはschema.rbを**読まない**
- 実際のAPI実行結果から生成
- マイグレーション方式（Rails標準 or Ridgepole）は無関係

---

### フロー全体

```
1. Schemafile更新（Ridgepole）
   ↓
2. ridgepole --apply
   ↓
3. Modelファイル作成/更新
   ↓
4. Controller実装
   ↓
5. RSpecテスト作成
   ↓
6. OPENAPI=1 rspec  ← OpenAPI自動生成
   ↓
7. docs/openapi.yaml 確認
   ↓
8. （必要に応じて）手動微調整
```

---

## 運用フロー

### Phase 1: 手動管理（現在）

```
✅ docs/openapi.yaml を手動作成・管理
✅ 仕様を細かく制御できる
✅ 学習コスト低い
```

**適用タイミング**:
- API数が少ない
- 仕様が頻繁に変わらない
- 細かい制御が必要

---

### Phase 2: 併用運用（推奨次ステップ）

```
1. OPENAPI=1 rspec で自動生成
   ↓
2. docs/openapi.yaml を確認
   ↓
3. 必要に応じて手動微調整
   ↓
4. gitコミット
```

**メリット**:
- ✅ 基本構造は自動生成
- ✅ 説明文等は手動追加
- ✅ 柔軟性とメンテナンス性の両立

---

### Phase 3: 完全自動化（将来）

```
1. OPENAPI=1 rspec で自動生成
   ↓
2. CI/CDでバリデーション
   ↓
3. 自動デプロイ
```

**適用タイミング**:
- API数が多い
- 頻繁な変更
- チーム規模が大きい

---

## 注意点・制限事項

### ✅ 自動生成できるもの

- エンドポイント（パス、メソッド）
- パラメータ（パス、クエリ）
- レスポンススキーマ（実際のレスポンスから）
- ステータスコード
- 基本的な型情報

---

### ❌ 自動生成できないもの（手動追加推奨）

#### 1. 詳細な説明文

```yaml
# 自動生成
paths:
  /users/{id}:
    get:
      # ← 説明なし

# 手動追加推奨
paths:
  /users/{id}:
    get:
      summary: ユーザーID指定取得
      description: |
        指定したユーザーIDの情報を取得します。
        存在しないIDの場合は404を返します。
```

---

#### 2. 複数のexamples

```yaml
# 自動生成: 1つの例のみ
examples:
  example1:
    value: {...}

# 手動追加推奨: 複数パターン
examples:
  success:
    summary: 成功時
    value: {...}
  notFound:
    summary: 該当なし
    value: []
```

---

#### 3. バリデーションルール詳細

```yaml
# 自動生成
email:
  type: string

# 手動追加推奨
email:
  type: string
  format: email
  pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  minLength: 5
  maxLength: 255
```

---

#### 4. ビジネスロジックの説明

```yaml
# 手動追加推奨
description: |
  ## 認証
  Basic認証が必要です。client_id/client_secretを使用してください。

  ## IP制限
  登録されたIPアドレスからのみアクセス可能です。

  ## レート制限
  1分間に60リクエストまで。
```

---

### 運用上の注意

#### 1. テストデータの整合性

```ruby
# ❌ 悪い例: ランダムデータ
user = create(:user, email: Faker::Internet.email)

# ✅ 良い例: 固定データ
user = create(:user, email: 'test@example.com', name: '山田太郎')
```

**理由**: OpenAPI仕様書の例として分かりやすい

---

#### 2. 認証ヘッダーの統一

```ruby
# spec/support/api_helper.rb
module ApiHelper
  def auth_header(client_id: 'test_client', client_secret: 'test_secret')
    credentials = Base64.strict_encode64("#{client_id}:#{client_secret}")
    { 'Authorization' => "Basic #{credentials}" }
  end
end

RSpec.configure do |config|
  config.include ApiHelper, type: :request
end

# テストで使用
get '/api/v1/users/1', headers: auth_header
```

---

#### 3. 生成後の確認

```bash
# 1. バリデーション
docker run --rm -v $(pwd):/workspace \
  openapitools/openapi-generator-cli validate \
  -i /workspace/docs/openapi.yaml

# 2. Swagger UIで確認
docker run -p 8081:8080 \
  -e SWAGGER_JSON=/openapi.yaml \
  -v $(pwd)/docs/openapi.yaml:/openapi.yaml \
  swaggerapi/swagger-ui

# 3. 差分確認
git diff docs/openapi.yaml
```

---

## 参考リンク

- [rspec-openapi GitHub](https://github.com/exoego/rspec-openapi)
- [OpenAPI Specification 3.0.3](https://swagger.io/specification/)
- [Swagger UI](https://swagger.io/tools/swagger-ui/)
- [Ridgepole](https://github.com/ridgepole/ridgepole)

---

## まとめ

### 推奨ツール: rspec-openapi

**理由**:
- ✅ 既存RSpecテストから自動生成
- ✅ 学習コスト低い
- ✅ Ridgepoleと完全独立
- ✅ テストと仕様の一致を保証

### 運用戦略

```
Phase 1（現在）: 手動管理
  ↓ API数増加・変更頻度上昇
Phase 2（次）: 自動生成 + 手動微調整
  ↓ さらに規模拡大
Phase 3（将来）: 完全自動化
```

### セットアップ

```bash
# 1. インストール
bundle add rspec-openapi --group development,test

# 2. 設定（spec/rails_helper.rb）
config.openapi_root = Rails.root.join('docs').to_s

# 3. 生成
OPENAPI=1 bundle exec rspec spec/requests
```

---

**作成日**: 2025-10-28
**対象プロジェクト**: sso-idp
**関連ドキュメント**: `notes/api-specification.md`, `docs/openapi.yaml`
