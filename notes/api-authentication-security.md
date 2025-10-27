# API認証とセキュリティ - client_id/secret の安全性

**Date**: 2025-10-27

## 結論

**client_id/secret を HTTPS + サーバーサイドで使用するのは安全であり、OAuth 2.0 の業界標準**

---

## 1. なぜ安全なのか？

### 前提条件

```
RP Server (backend)
  └─ HTTPS通信 ─→ IdP API
     └─ Authorization: Basic <Base64(client_id:client_secret)>
```

### ✅ 安全性の根拠

| 要素 | 安全性への寄与 |
|------|--------------|
| **HTTPS** | 通信が暗号化されるため、盗聴不可 |
| **サーバーサイド処理** | ブラウザに secret を露出しない |
| **環境変数管理** | コードリポジトリに含めない（.gitignore） |
| **サーバー間通信** | ユーザーのブラウザを経由しない |

### 通信の流れ

```
1. RP Server 起動時
   ├─ 環境変数から client_secret 読み込み
   └─ メモリ上に保持（ファイルシステムに残さない）

2. API呼び出し時
   ├─ サーバー内で Basic認証ヘッダー生成
   ├─ HTTPS で IdP に送信（暗号化）
   └─ レスポンス受信

3. ブラウザ
   └─ secret を一切知らない（見えない、触れない）
```

---

## 2. OAuth 2.0 標準仕様

### RFC 6749 - The OAuth 2.0 Authorization Framework

**セクション 2.3.1 - Client Password**

> Clients in possession of a client password MAY use the HTTP Basic
> authentication scheme as defined in [RFC2617] to authenticate with
> the authorization server.

**標準的な使用方法**:

```http
Authorization: Basic <Base64(client_id:client_secret)>
```

これは OAuth 2.0 の **公式な Client Authentication 方法** です。

### Client Credentials Flow

**用途**: サーバー間通信、Machine-to-Machine認証

```http
POST /oauth2/token
Authorization: Basic <Base64(client_id:client_secret)>
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=...
```

**今回の RP管理API も同じパターン**:

```http
GET /api/v1/users/123
Authorization: Basic <Base64(client_id:client_secret)>
```

---

## 3. 業界標準：主要APIサービスの実装例

### GitHub API

```bash
curl -u "client_id:client_secret" \
  https://api.github.com/user

# または
curl -H "Authorization: Basic $(echo -n 'client_id:client_secret' | base64)" \
  https://api.github.com/user
```

**ドキュメント**: [GitHub OAuth Apps](https://docs.github.com/en/apps/oauth-apps)

---

### Google Cloud API

```http
POST https://oauth2.googleapis.com/token
Authorization: Basic <Base64(client_id:client_secret)>
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=https://www.googleapis.com/auth/cloud-platform
```

**ドキュメント**: [Using OAuth 2.0 for Server to Server Applications](https://developers.google.com/identity/protocols/oauth2/service-account)

---

### Stripe API

```bash
curl https://api.stripe.com/v1/charges \
  -u "sk_test_xxx:"
  # API Key = Secret Key
```

**ドキュメント**: [Stripe Authentication](https://stripe.com/docs/api/authentication)

**注**: Stripe の Secret Key は client_secret と同じ概念

---

### AWS API

```bash
# ~/.aws/credentials
[default]
aws_access_key_id = YOUR_ACCESS_KEY      # ≒ client_id
aws_secret_access_key = YOUR_SECRET_KEY  # ≒ client_secret

# API呼び出し
aws s3 ls --profile default
```

**ドキュメント**: [AWS Security Credentials](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html)

---

### Slack API

```http
POST https://slack.com/api/chat.postMessage
Authorization: Bearer xoxb-your-app-token
Content-Type: application/json

{"channel": "C1234567890", "text": "Hello"}
```

**ドキュメント**: [Slack Authentication](https://api.slack.com/authentication)

**注**: Bot Token は secret として扱われる

---

### Twitter (X) API

```http
POST https://api.twitter.com/2/tweets
Authorization: Bearer YOUR_BEARER_TOKEN
Content-Type: application/json

{"text": "Hello World"}
```

**ドキュメント**: [Twitter API Authentication](https://developer.twitter.com/en/docs/authentication)

---

### その他の主要サービス

| サービス | 認証方式 | client_secret使用 |
|---------|---------|------------------|
| Facebook API | OAuth 2.0 | ✅ |
| Microsoft Azure | OAuth 2.0 | ✅ |
| Salesforce API | OAuth 2.0 | ✅ |
| Twilio API | Basic Auth (Account SID + Auth Token) | ✅ |
| SendGrid API | API Key | ✅ |
| Heroku API | Bearer Token | ✅ |

**共通点**: すべて HTTPS + サーバーサイドで secret を使用

---

## 4. 安全 vs 危険：比較

### ✅ 安全なパターン（推奨）

#### Node.js / Express 例

```javascript
// server.js（サーバーサイド）
const axios = require('axios');

const clientId = process.env.CLIENT_ID;
const clientSecret = process.env.CLIENT_SECRET;
const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');

app.get('/api/users/:id', async (req, res) => {
  try {
    const response = await axios.get(
      `https://idp.example.com/api/v1/users/${req.params.id}`,
      {
        headers: {
          'Authorization': `Basic ${credentials}`
        }
      }
    );
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});
```

**なぜ安全？**
- ✅ サーバーサイドのコード（ブラウザで実行されない）
- ✅ 環境変数から読み込み（`.env` は gitignore）
- ✅ HTTPS通信
- ✅ client_secret がブラウザに一切露出しない

---

#### Ruby / Rails 例

```ruby
# app/services/idp_api_client.rb
class IdpApiClient
  def initialize
    @client_id = ENV['CLIENT_ID']
    @client_secret = ENV['CLIENT_SECRET']
  end

  def get_user(user_id)
    uri = URI("https://idp.example.com/api/v1/users/#{user_id}")
    request = Net::HTTP::Get.new(uri)
    request.basic_auth(@client_id, @client_secret)

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  end
end
```

**なぜ安全？**
- ✅ サーバーサイドのRubyコード
- ✅ 環境変数から読み込み
- ✅ HTTPS通信（`use_ssl: true`）
- ✅ client_secret がクライアントに送られない

---

### ❌ 危険なパターン（絶対NG）

#### ブラウザの JavaScript

```html
<!-- public/index.html（絶対ダメ！） -->
<script>
// ❌ ソースコードに直接記載
const clientId = 'abc123';
const clientSecret = 'xyz789secret';  // ← 誰でも見える！

const credentials = btoa(`${clientId}:${clientSecret}`);

fetch('https://idp.example.com/api/v1/users/123', {
  headers: {
    'Authorization': `Basic ${credentials}`
  }
})
.then(response => response.json())
.then(data => console.log(data));
</script>
```

**なぜ危険？**
- ❌ ブラウザの開発者ツールで見える（F12キー）
- ❌ ページのソースコードに含まれる
- ❌ ネットワークタブでリクエストヘッダーが見える
- ❌ 誰でも client_secret を取得できる
- ❌ 取得した secret で不正なAPIアクセスが可能

---

#### 環境変数を使っても危険（ブラウザの場合）

```javascript
// React/Vue など（フロントエンド）
// .env.local
// REACT_APP_CLIENT_SECRET=xyz789  # ← ビルド時にバンドルされる

// App.js
const clientSecret = process.env.REACT_APP_CLIENT_SECRET;  // ❌ 危険！
```

**なぜ危険？**
- ❌ ビルドされた JavaScript に含まれる
- ❌ バンドルファイル（bundle.js）を開けば見える
- ❌ ブラウザで実行されるコード = クライアントサイド

**正しい方法**: バックエンドAPIを経由する

```javascript
// フロントエンド（React）
fetch('/api/users/123')  // ← 自分のバックエンドAPI

// バックエンド（Node.js）
app.get('/api/users/:id', (req, res) => {
  // ここで client_secret を使って IdP API を呼ぶ
});
```

---

## 5. セキュリティのベストプラクティス

### 1. HTTPS強制

```nginx
# nginx.conf
server {
    listen 443 ssl http2;
    # HTTP は自動的にHTTPSへリダイレクト
}

server {
    listen 80;
    return 301 https://$server_name:4443$request_uri;
}
```

**本番環境**: Let's Encrypt 等で正式な証明書を使用

---

### 2. 環境変数で管理

```bash
# .env（gitignore対象）
CLIENT_ID=abc123
CLIENT_SECRET=xyz789secret

# .env.example（リポジトリにコミット）
CLIENT_ID=your_client_id
CLIENT_SECRET=your_client_secret
```

```gitignore
# .gitignore
.env
.env.local
```

---

### 3. ローテーション（定期的な更新）

```bash
# 本番環境では定期的にsecretを更新
# 例: 3ヶ月ごと、6ヶ月ごと

# 1. 新しいクライアント登録
./register-client.sh "https://rp.example.com/callback"

# 2. RP側の環境変数を更新
CLIENT_ID=new_abc123
CLIENT_SECRET=new_xyz789

# 3. デプロイ後、古いクライアントを無効化
docker-compose exec web rails console
RpClient.find_by(client_id: 'old_abc123').update(active: false)
```

---

### 4. アクセスログ・監視

```ruby
# app/controllers/api/v1/users_controller.rb
def authenticate_rp_client
  # 認証失敗をログに記録
  unless rp_client
    Rails.logger.warn "Authentication failed: #{client_id} from #{request.remote_ip}"
    render json: { error: 'Invalid credentials' }, status: :unauthorized
    return
  end

  # 成功もログに記録（監査用）
  Rails.logger.info "API access: client=#{rp_client.name}, ip=#{request.remote_ip}, endpoint=#{request.path}"
end
```

---

### 5. Rate Limiting（将来的に）

```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle('api/ip', limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api/')
end

Rack::Attack.throttle('api/client', limit: 1000, period: 1.hour) do |req|
  # client_id でレート制限
  if req.path.start_with?('/api/v1/users')
    # Basic認証からclient_idを抽出
    extract_client_id(req.env['HTTP_AUTHORIZATION'])
  end
end
```

---

## 6. 今回の RP管理API の設計評価

### ✅ OAuth 2.0 標準に準拠

```
RP Server → IdP API
  GET /api/v1/users/123
  Authorization: Basic <Base64(client_id:client_secret)>
```

| 項目 | 評価 |
|------|------|
| OAuth 2.0 準拠 | ✅ Yes（Client Credentials相当） |
| HTTPS必須 | ✅ Yes |
| サーバー間通信 | ✅ Yes |
| 環境変数管理 | ✅ Yes |
| IP制限（追加防御） | ✅ Yes（Defense in Depth） |

### さらに安全性を高める要素

**IP制限の追加**:
```ruby
# OAuth 2.0 標準 + 独自の強化
def authenticate_rp_client
  # 1. Basic認証（OAuth 2.0標準）
  verify_basic_auth

  # 2. IP制限（追加の防御層）
  verify_ip_restriction
end
```

これは **Defense in Depth（多層防御）** の原則に基づく設計です。

---

## 7. まとめ

### 質問への回答

| 質問 | 回答 |
|------|------|
| **HTTPS + サーバーサイドなら client_secret は安全？** | **✅ Yes** |
| **これは業界標準？** | **✅ Yes（OAuth 2.0標準）** |
| **主要APIサービスも同じ方式？** | **✅ Yes（GitHub, Google, AWS, Stripe等）** |

### 重要なポイント

1. **HTTPS必須** - 通信暗号化
2. **サーバーサイドのみ** - ブラウザに露出しない
3. **環境変数管理** - コードリポジトリに含めない
4. **OAuth 2.0標準** - 業界のベストプラクティス

### 今回の設計の正当性

**RP管理API の Basic認証（client_id/secret）は**:
- ✅ 技術的に安全
- ✅ 業界標準に準拠
- ✅ 主要サービスと同じパターン
- ✅ OAuth 2.0 の公式な方法

**自信を持って実装を進めてOK！** 💪

---

## 参考資料

- [RFC 6749 - The OAuth 2.0 Authorization Framework](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 2617 - HTTP Authentication: Basic and Digest Access Authentication](https://datatracker.ietf.org/doc/html/rfc2617)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [OAuth 2.0 Security Best Current Practice](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics)

---

**作成日**: 2025-10-27
**関連ドキュメント**: `notes/rp-management-api-spec-beta.md`
