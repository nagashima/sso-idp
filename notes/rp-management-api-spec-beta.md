# RP管理API仕様書 (β版)

**Version**: 0.1.0-beta
**Date**: 2025-10-27
**Status**: Draft for Review

---

## 📋 目次

1. [背景・目的](#背景目的)
2. [全体アーキテクチャ](#全体アーキテクチャ)
3. [データモデル](#データモデル)
4. [API仕様](#api仕様)
5. [認証フロー](#認証フロー)
6. [セキュリティ](#セキュリティ)
7. [実装スコープ](#実装スコープ)
8. [今後の検討事項](#今後の検討事項)

---

## 背景・目的

### 要件

複数のRP（Relying Party）サイトの会員情報をIdPで統合管理し、以下を実現する：

1. **ログイン中のユーザー情報取得** → OIDC標準フロー（既存）
2. **任意のユーザー情報取得** → 新規API（本仕様）
   - ログインしていないユーザー情報も含む
   - RPサーバーからサーバー間通信で取得

### ユースケース

- RP1でログインしたユーザーの情報を、RP2から取得
- ユーザーID/メールアドレスによる検索
- 複数ユーザーの一括取得

---

## 全体アーキテクチャ

### システム構成

```
┌─────────────────────────────────────────────────┐
│              IdP (Rails + Hydra)                │
│                                                 │
│  ┌──────────────┐      ┌──────────────┐        │
│  │    Hydra     │      │    Rails     │        │
│  │ OAuth2 Server│◄────►│   IdP App    │        │
│  │              │      │              │        │
│  │ - client登録 │      │ - RpClient   │        │
│  │ - token発行  │      │   管理       │        │
│  └──────────────┘      │ - User管理   │        │
│    ↑ Admin API(4445)   │ - API提供    │        │
│    │ 認証不要(内部)      └──────────────┘        │
└─────────────────────────────────────────────────┘
           ▲                      ▲
           │                      │
     OIDC フロー          API呼び出し
           │                      │
┌──────────┴───────┐    ┌─────────┴──────┐
│   RP1 Server     │    │  RP2 Server    │
│ (localhost:3443) │    │ (hogehoge.jp)  │
└──────────────────┘    └────────────────┘
```

**注記**:
- IdP (Rails) は Hydra に client として登録されていません
- Rails → Hydra Admin API (4445) の通信は Docker 内部ネットワークで認証不要
- RP1, RP2 のみが Hydra に OAuth2 client として登録されます

### データフロー

#### 既存：OIDCログインフロー
```
RP → Hydra → IdP認証 → トークン発行 → /userinfo → ログイン中のユーザー情報
```

#### 新規：RP管理APIフロー
```
RP Server → /api/v1/users (Basic認証)
          → IP制限チェック
          → 任意のユーザー情報を返却
```

---

## データモデル

### RpClient (新規テーブル)

RPクライアントの登録情報を管理。Hydraの登録情報と連携。

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_rp_clients.rb
create_table :rp_clients do |t|
  t.string :client_id, null: false, index: { unique: true }
  t.string :client_secret, null: false
  t.string :name, null: false
  t.text :allowed_ips
  t.boolean :active, default: true, null: false
  t.timestamps
end
```

#### カラム説明

| カラム | 型 | 説明 |
|--------|------|------|
| `client_id` | string | Hydraで発行されたclient_id（一意） |
| `client_secret` | string | Hydraで発行されたclient_secret |
| `name` | string | RP識別名（例: localhost:3443, hogehoge.jp） |
| `allowed_ips` | text | 許可IPリスト（カンマ区切り） |
| `active` | boolean | 有効/無効フラグ |

#### モデル実装

```ruby
class RpClient < ApplicationRecord
  validates :client_id, presence: true, uniqueness: true
  validates :client_secret, presence: true
  validates :name, presence: true

  # IPリストを配列として取得
  def allowed_ip_list
    allowed_ips&.split(',')&.map(&:strip) || []
  end

  # IPが許可されているかチェック
  def ip_allowed?(ip)
    return true if allowed_ips.blank?  # 空の場合は全許可（開発用）
    allowed_ip_list.include?(ip)
  end
end
```

---

## API仕様

### Base URL

```
https://localhost:4443/api/v1
```

本番環境では適切なドメインに置き換え。

### 認証

すべてのエンドポイントで以下の認証が必要：

```http
Authorization: Basic <Base64(client_id:client_secret)>
```

- `client_id`: RpClientに登録されたclient_id
- `client_secret`: RpClientに登録されたclient_secret

### エンドポイント

#### 1. ユーザーID指定取得

**Endpoint**: `GET /api/v1/users/:id`

**説明**: 指定したユーザーIDの情報を取得

**Request**:
```http
GET /api/v1/users/123
Authorization: Basic Y2xpZW50X2lkOmNsaWVudF9zZWNyZXQ=
```

**Response** (200 OK):
```json
{
  "id": 123,
  "email": "user@example.com",
  "name": "山田太郎",
  "birth_date": "1990-01-01",
  "phone_number": "090-1234-5678",
  "address": "東京都渋谷区...",
  "activated": true
}
```

**Response** (404 Not Found):
```json
{
  "error": "User not found"
}
```

---

#### 2. メールアドレス検索

**Endpoint**: `GET /api/v1/users?email=xxx`

**説明**: 指定したメールアドレスのユーザー情報を取得

**Request**:
```http
GET /api/v1/users?email=user@example.com
Authorization: Basic Y2xpZW50X2lkOmNsaWVudF9zZWNyZXQ=
```

**Response**: ユーザーID指定取得と同じ

---

#### 3. 複数ユーザー一括取得

**Endpoint**: `GET /api/v1/users?ids=xxx`

**説明**: 複数のユーザーIDを指定して一括取得

**Request**:
```http
GET /api/v1/users?ids=1,2,3
Authorization: Basic Y2xpZW50X2lkOmNsaWVudF9zZWNyZXQ=
```

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "email": "user1@example.com",
    "name": "ユーザー1",
    ...
  },
  {
    "id": 2,
    "email": "user2@example.com",
    "name": "ユーザー2",
    ...
  }
]
```

---

### エラーレスポンス

| ステータスコード | 説明 | レスポンス例 |
|-----------------|------|-------------|
| 400 Bad Request | パラメータ不正 | `{"error": "Missing parameter"}` |
| 401 Unauthorized | 認証失敗 | `{"error": "Invalid credentials"}` |
| 403 Forbidden | IP制限により拒否 | `{"error": "IP not allowed"}` |
| 404 Not Found | ユーザーが存在しない | `{"error": "User not found"}` |

---

## 認証フロー

### 1. RP登録時（管理者操作）

```bash
# スクリプト実行
./scripts/register-client.sh \
  "https://rp.example.com/callback" \
  --first-party \
  --allowed-ips "192.168.1.10,192.168.1.20"

# ↓

# 1. Hydraにclient登録
client_id: abc123...
client_secret: xyz789...

# 2. Rails DBに登録
RpClient.create!(
  client_id: 'abc123...',
  client_secret: 'xyz789...',
  name: 'rp.example.com',
  allowed_ips: '192.168.1.10,192.168.1.20',
  active: true
)
```

### 2. API呼び出し時（RP Server）

```
1. RP Server → IdP API
   Authorization: Basic <Base64(client_id:client_secret)>

2. IdP (Rails) 認証処理
   a. Basic認証ヘッダーをデコード
   b. RpClient テーブルで client_id/secret を照合
   c. active=true を確認
   d. request.remote_ip が allowed_ips に含まれるか確認

3. すべて通過
   → ユーザー情報を返却

4. いずれか失敗
   → 401 Unauthorized or 403 Forbidden
```

---

## セキュリティ

### 前提条件

| 項目 | 要件 |
|------|------|
| 通信プロトコル | **HTTPS必須** |
| 通信形態 | **サーバー間通信のみ** |
| 認証方式 | Basic認証（client_id/secret） + IP制限 |
| ブラウザからのアクセス | **不可**（CORSで制限） |

### セキュリティ対策

1. **HTTPS強制**
   - 本番環境では平文HTTP通信を拒否

2. **client_secret管理**
   - 環境変数で管理（`.env`、gitignore対象）
   - ログに出力しない
   - DB保存時のハッシュ化は検討事項

3. **IP制限**
   - `allowed_ips` に登録されたIPのみ許可
   - 空の場合は開発環境のみ全許可（本番では必須）

4. **アクセスログ**
   - 認証失敗をログに記録
   - 異常なアクセスパターンの検知

5. **Rate Limiting**
   - 将来的に実装を検討（Rack::Attack等）

### 開発環境での注意点

- Dockerコンテナ間通信の場合、`request.remote_ip` はコンテナのIPになる
- 開発時は `allowed_ips` を空にして制限を緩和する選択肢も

---

## 実装スコープ

### Phase 1: 基本実装（本仕様）

- [x] RpClient モデル作成
- [x] マイグレーション
- [x] API Controller 実装
  - `/api/v1/users/:id`
  - `/api/v1/users?email=xxx`
  - `/api/v1/users?ids=1,2,3`
- [x] Basic認証 + IP制限
- [x] `register-client.sh` の拡張（`--allowed-ips` オプション）

### Phase 2: 拡張機能（将来）

- [ ] Rate Limiting
- [ ] アクセスログ詳細化
- [ ] client_secret のハッシュ化
- [ ] 管理画面（RpClient CRUD）
- [ ] ページネーション（大量ユーザー対応）
- [ ] フィールド選択（必要な属性のみ返却）

---

## 今後の検討事項

### 1. client_secret のハッシュ化

**現状**: 平文でDB保存
**検討**: bcryptでハッシュ化（`has_secure_password`等）

**メリット**:
- DB漏洩時の被害軽減

**デメリット**:
- Hydraと照合が必要な場合に複雑化
- 現状は「Hydraの値を流用するだけ」なので平文で十分かも

**結論**: Phase 2で検討

---

### 2. IP制限の実装レベル

**選択肢**:
- **A. Rails レベル**: 現仕様（柔軟、DB管理）
- **B. nginx レベル**: より高速、設定が分散

**結論**: まずはRailsレベルで実装し、パフォーマンス問題があればnginxへ移行

---

### 3. スコープベースの情報制限

**現状**: すべての情報を返す

**検討**: RPごとに取得可能な属性を制限
```ruby
# 例: RpClient に allowed_fields を追加
allowed_fields: "id,email,name"  # birth_date, phone は取得不可
```

**結論**: first-party前提なので当面は不要。third-party対応時に再検討

---

### 4. 既存 `/api/v1/user_info` との統合

**現状**:
- `/api/v1/user_info`: アクセストークンベース（ログイン中のユーザー自身）
- `/api/v1/users`: client_id/secretベース（任意のユーザー）

**検討**: 統合の必要性

**結論**: 用途が異なるため分離して保持

| エンドポイント | 用途 | 認証 | 対象 |
|---------------|------|------|------|
| `/api/v1/user_info` | OIDCログイン後のプロフィール表示 | Access Token | ログイン中のユーザー |
| `/api/v1/users/*` | RP統合管理 | client_id/secret | 全ユーザー |

---

### 5. RP登録スクリプトの自動化

**検討**: Rails DBへの登録をスクリプト内で自動化

```bash
# 案1: スクリプト内でRails runnerを実行
docker-compose exec web bundle exec rails runner "..."

# 案2: Hydra登録後にWebhookでRailsに通知

# 案3: 管理画面で手動登録
```

**結論**: Phase 1では案1（スクリプト内実行）で実装

---

## Appendix

### RP側の実装例

```ruby
# RP側のコード例（Ruby）
require 'net/http'
require 'json'
require 'base64'

class IdpApiClient
  def initialize
    @base_url = ENV['IDP_API_URL']  # https://localhost:4443/api/v1
    @client_id = ENV['OAUTH_CLIENT_ID']
    @client_secret = ENV['OAUTH_CLIENT_SECRET']
  end

  def get_user(user_id)
    uri = URI("#{@base_url}/users/#{user_id}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = basic_auth_header

    response = http_client(uri).request(request)

    case response.code
    when '200'
      JSON.parse(response.body)
    when '404'
      nil
    else
      raise "API Error: #{response.code} #{response.body}"
    end
  end

  def find_by_email(email)
    uri = URI("#{@base_url}/users?email=#{CGI.escape(email)}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = basic_auth_header

    response = http_client(uri).request(request)

    response.code == '200' ? JSON.parse(response.body) : nil
  end

  private

  def basic_auth_header
    credentials = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    "Basic #{credentials}"
  end

  def http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http
  end
end

# 使用例
client = IdpApiClient.new
user = client.get_user(123)
puts user['name']  # => "山田太郎"
```

---

## 変更履歴

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0-beta | 2025-10-27 | 初版作成 |

---

**End of Document**
