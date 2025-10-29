# 段階的移行ガイド - Phase 1（必須）→ Phase 2（オプション）

## 📋 前提

このガイドは以下のドキュメントを前提としています：
- `nginx-configuration.md` - 現在のnginx構成の理解
- `idp-distribution-strategy.md` - 移行戦略とパターン（Phase 2選択肢の比較も参照）

## 🎯 段階的移行の意図

### なぜ段階的に移行するのか？

**直接移行の問題点**:
```
idp.localhost + nginx → localhost:4443 + Caddy
└─ 2つの変更を同時に実施（問題の切り分けが困難）
```

**段階的移行のメリット**:
```
Phase 1: idp.localhost + nginx → localhost:4443 + nginx（必須）
         └─ ドメイン/ポート変更の影響を検証
         └─ Cookie、CORSの動作確認
         └─ 動作確認済みのnginx設定を活用
         └─ 主要目標達成（/etc/hosts不要）

Phase 2: 証明書自動化（オプション）
         ├─ Phase 2-A: https-portal（推奨）
         │   └─ nginx設定をほぼ継承、動作確実性が高い
         └─ Phase 2-B: Caddy（参考）
             └─ 設定シンプル、新規検証が必要
```

### 重点検証ポイント

**特に注意が必要な領域**:
1. **Cookie動作** - `SameSite=None; Secure` の挙動
2. **CORS** - Cross-Origin Resource Sharing
3. **CSRF対策** - セッション維持とトークン検証
4. **Hydraリダイレクト** - OAuth2フロー全体

### ⚠️ 重要: sso-rp側の協調修正が必要

**Phase 1では sso-rp側も修正が必須です**：

| Phase | IdP側の変更 | RP側の変更 |
|-------|------------|-----------|
| **Phase 1** | `idp.localhost` → `localhost:4443`<br>nginx継続 | ✅ **必要**<br>`.env.local` と `docker-compose.yml` 修正 |
| **Phase 2** | nginx → https-portal/Caddy<br>`localhost:4443` 継続<br>証明書自動化 | ❌ 不要<br>Phase 1の設定をそのまま使用 |

**Phase 1でRP側修正が必要な理由**:
- RPコンテナ内から `localhost:4443` にアクセスできない
- `host.docker.internal` を使った設定が必要
- 詳細は「検証1-5」を参照

---

## 🔄 Phase 1: nginx で localhost:4443 に移行

### 目的

- ドメイン変更（`idp.localhost` → `localhost`）
- ポート変更（`443` → `4443`）
- **動作確認済みのnginx設定**を活用して、ドメイン/ポート変更の影響を検証

### Phase 1の実装手順

#### Step 1-1: SSL証明書の再生成

```bash
cd docker/nginx/ssl

# 既存の証明書をバックアップ
mv localhost.crt localhost.crt.backup
mv localhost.key localhost.key.backup

# 新しい証明書を生成（CN=localhost）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout localhost.key \
  -out localhost.crt \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Dev/CN=localhost"

# 確認
openssl x509 -in localhost.crt -text -noout | grep Subject:
# 期待: Subject: C = JP, ST = Tokyo, L = Tokyo, O = Dev, CN = localhost
```

---

#### Step 1-2: nginx.conf の修正

`docker/nginx/nginx.conf`:

**変更前**:
```nginx
server {
    listen 80;
    server_name idp.localhost;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name idp.localhost;
    # ...
}
```

**変更後**:
```nginx
server {
    listen 80;
    server_name localhost;
    return 301 https://$server_name:4443$request_uri;  # ポート番号を明示
}

server {
    listen 443 ssl http2;
    server_name localhost;

    # SSL証明書設定（変更なし）
    ssl_certificate /etc/nginx/ssl/localhost.crt;
    ssl_certificate_key /etc/nginx/ssl/localhost.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # セキュリティヘッダー（変更なし）
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # プロキシヘッダー設定（変更なし）
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Port 443;
    proxy_redirect off;
    proxy_cookie_flags ~ secure;

    # パスベースルーティング（変更なし）
    location /auth/ {
        proxy_pass http://web:3000;
    }

    location /oauth2/ {
        proxy_pass http://hydra:4444;
    }

    location /health/ {
        proxy_pass http://hydra:4444;
    }

    location /.well-known/ {
        proxy_pass http://hydra:4444;
    }

    location /userinfo {
        proxy_pass http://hydra:4444/userinfo;
    }

    location / {
        proxy_pass http://web:3000;
    }
}
```

**重要**: `X-Forwarded-Port` は `443` のまま（コンテナ内部では443番ポート）

---

#### Step 1-3: docker-compose.yml の修正

**変更前**:
```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
      - "80:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - web
      - hydra
```

**変更後**:
```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "4443:443"  # ホストの4443 → コンテナの443
      - "8080:80"   # ホストの8080 → コンテナの80（HTTPリダイレクト用）
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - web
      - hydra
```

---

#### Step 1-4: 環境変数の修正（.env）

```bash
# 変更前
HOST_NAME=idp.localhost
HOST_PORT=443
HYDRA_PUBLIC_URL=https://idp.localhost

# 変更後
HOST_NAME=localhost
HOST_PORT=4443
HYDRA_PUBLIC_URL=https://localhost:4443
```

---

#### Step 1-5: Rails設定の確認

`config/application.rb` または `config/environments/development.rb`:

```ruby
# ホスト許可設定
config.hosts << "localhost"
config.hosts << "idp.localhost"  # 後方互換のため残しても良い

# HTTPS強制（X-Forwarded-Proto を信頼）
config.force_ssl = true
```

**確認**: Rails が `X-Forwarded-Proto: https` を信頼する設定になっているか

---

#### Step 1-6: Hydra設定の確認

`docker/hydra/hydra.yml`:

```yaml
# URLエンドポイント設定を確認
urls:
  self:
    issuer: https://localhost:4443
  login: https://localhost:4443/auth/login
  consent: https://localhost:4443/auth/consent
  logout: https://localhost:4443/auth/logout

# CORS設定を確認
serve:
  public:
    cors:
      enabled: true
      allowed_origins:
        - https://localhost:3443  # RP側のオリジン
```

---

#### Step 1-7: 起動と初期確認

```bash
# コンテナ停止・削除
docker-compose down

# データベースは保持（クライアント登録を維持）
# もし完全にクリーンスタートする場合:
# docker-compose down -v

# 再起動
docker-compose up -d

# ログ確認
docker-compose logs -f nginx
docker-compose logs -f web
docker-compose logs -f hydra

# nginxの設定確認
docker-compose exec nginx nginx -t

# Hydraヘルスチェック
curl -k https://localhost:4443/health/ready

# IdPトップページ
curl -k https://localhost:4443
```

---

### Phase 1の検証手順 🔍

#### 検証1-1: HTTPS接続

```bash
# ブラウザでアクセス
https://localhost:4443

# 期待: 自己署名証明書の警告（OK）
# 確認: IdPトップページが表示される
```

**確認ポイント**:
- ✅ ブラウザのアドレスバーに `https://localhost:4443` が表示
- ✅ 証明書エラー（自己署名のため正常）
- ✅ ページが正常に表示される

---

#### 検証1-2: リバースプロキシ動作

```bash
# Rails へのルーティング
curl -k https://localhost:4443/
curl -k https://localhost:4443/auth/login

# Hydra へのルーティング
curl -k https://localhost:4443/oauth2/auth
curl -k https://localhost:4443/health/ready
curl -k https://localhost:4443/.well-known/openid-configuration
```

**期待**: それぞれ正しいバックエンドからレスポンスが返る

---

#### 検証1-3: プロキシヘッダー伝播 ⭐ 重要

**一時的なヘッダーロギング追加**:

`config/application.rb` に追加:

```ruby
# Phase 1検証用 - ヘッダーログ出力
class HeaderLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    Rails.logger.info "=== Request Headers (Phase 1) ==="
    Rails.logger.info "X-Forwarded-Proto: #{env['HTTP_X_FORWARDED_PROTO']}"
    Rails.logger.info "X-Forwarded-Host: #{env['HTTP_X_FORWARDED_HOST']}"
    Rails.logger.info "X-Forwarded-Port: #{env['HTTP_X_FORWARDED_PORT']}"
    Rails.logger.info "X-Forwarded-For: #{env['HTTP_X_FORWARDED_FOR']}"
    Rails.logger.info "Host: #{env['HTTP_HOST']}"
    Rails.logger.info "Request URL: #{env['REQUEST_URI']}"
    @app.call(env)
  end
end

config.middleware.insert_before 0, HeaderLogger
```

**確認方法**:

```bash
# Railsコンテナを再起動
docker-compose restart web

# ブラウザで https://localhost:4443/ にアクセス

# ログ確認
docker-compose logs web | grep "Request Headers"
```

**期待される出力**:
```
X-Forwarded-Proto: https
X-Forwarded-Host: localhost:4443
X-Forwarded-Port: 443
Host: localhost:4443
```

**検証ポイント**:
- ✅ `X-Forwarded-Proto: https` が設定されている
- ✅ `Host` が `localhost:4443` になっている

---

#### 検証1-4: Cookie動作 🍪 最重要

**シナリオ**: IdPでログインしてセッションCookieを発行

**手順**:

1. ブラウザで `https://localhost:4443/auth/login` にアクセス
2. メール・パスワードでログイン
3. **ブラウザ開発者ツール**を開く（F12）
4. **Application** → **Cookies** → `https://localhost:4443`

**確認項目**:

| Cookie | 確認ポイント | 期待値 |
|--------|-------------|--------|
| `_idp_session` | Secure属性 | ✅ チェック済み |
| `_idp_session` | SameSite | `None` または `Lax` |
| `_idp_session` | Domain | `localhost` |
| `_idp_session` | Path | `/` |
| `_idp_session` | HttpOnly | ✅ チェック済み（推奨） |

**スクリーンショット**: Cookie設定を確認

**検証ポイント**:
- ✅ **Secure属性が付与されている**（最重要）
- ✅ `SameSite=None` の場合、Secure必須
- ✅ ログイン後、ページ遷移してもCookieが維持される

**トラブルシューティング**:

もし Secure属性が付いていない場合:
1. nginx の `proxy_cookie_flags ~ secure;` を確認
2. Railsのセッション設定を確認:
   ```ruby
   # config/initializers/session_store.rb
   Rails.application.config.session_store :cookie_store,
     key: '_idp_session',
     secure: Rails.env.production? || Rails.application.config.force_ssl,
     same_site: :none,
     httponly: true
   ```

---

#### 検証1-5: CORS動作（RP連携準備） 🌐 最重要

**前提**: RP側が `https://localhost:3443` で動作

**⚠️ 重要**: sso-rp側も協調して修正が必要

---

**Step A: RP側の設定更新（コンテナ内アクセス対応）**

**問題**: RPコンテナ内から `localhost:4443` にアクセスできない

```
RPコンテナ内:
  localhost = コンテナ自身（127.0.0.1）
  localhost:4443 → コンテナ内のポート4443を探す → 何もない ❌
```

**解決策**: `host.docker.internal` を使用

`host.docker.internal` とは？
- **Docker特殊ホスト名**: コンテナからホストOSにアクセスするためのDNS名
- コンテナ内で `host.docker.internal:4443` → ホストOSの `localhost:4443` に転送される

**動作イメージ**:
```
┌─────────────────────────────────────┐
│ ホストOS                             │
│ └─ localhost:4443 → IdP             │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ RPコンテナ内                  │   │
│  │ localhost = 自分自身          │   │
│  │ host.docker.internal = ホストOS│  │
│  │   └→ ホストOSのポートにアクセス │  │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

---

**Step A-1: RP側の .env.local 修正**

RP側の `.env.local`:
```bash
# ブラウザリダイレクト用（ユーザーのブラウザで開くURL）
OAUTH_ISSUER=https://localhost:4443
OAUTH_AUTHORIZATION_URL=https://localhost:4443/oauth2/auth
OAUTH_REDIRECT_URI=https://localhost:3443/auth/callback

# バックエンド通信用（RPコンテナ内からのHTTPリクエスト）
OAUTH_TOKEN_URL=https://host.docker.internal:4443/oauth2/token
OAUTH_USERINFO_URL=https://host.docker.internal:4443/userinfo
OAUTH_JWKS_URL=https://host.docker.internal:4443/.well-known/jwks.json
```

**重要な使い分け**:
- **ブラウザ用URL**: `https://localhost:4443` - ユーザーのブラウザがアクセス
- **バックエンド用URL**: `https://host.docker.internal:4443` - RPサーバーがアクセス

---

**Step A-2: RP側の docker-compose.yml 修正**

RP側の `docker-compose.yml`:
```yaml
services:
  rp-app:
    # 既存の設定...

    extra_hosts:
      - "host.docker.internal:host-gateway"  # Linux用（Mac/Windowsでも害なし）
```

**プラットフォーム別の動作**:

| OS | `host.docker.internal` | `extra_hosts` 必要？ |
|----|------------------------|---------------------|
| **Mac** | 自動サポート（Docker Desktop） | ❌ 不要（あっても問題なし） |
| **Windows** | 自動サポート（Docker Desktop） | ❌ 不要（あっても問題なし） |
| **Linux** | サポートなし | ✅ **必須** |

**`host-gateway` とは？**:
- Docker 20.10+ の特殊値
- ホストOSのIPアドレスを自動解決
- Linux環境で `host.docker.internal` を使えるようにする

---

**Step A-3: SSL証明書検証の対処（必要に応じて）**

RPバックエンドから `host.docker.internal:4443` にアクセスする際、自己署名証明書のエラーが発生する可能性があります。

**オプション1: SSL検証を無効化（開発環境のみ）**

```ruby
# RP側 config/initializers/oauth.rb
require 'net/http'

uri = URI(ENV['OAUTH_TOKEN_URL'])
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # 開発環境のみ
```

**オプション2: curl/wgetでのアクセス**

```bash
# -k オプションで証明書検証をスキップ
curl -k https://host.docker.internal:4443/oauth2/token
```

---

**検証方法**:

```bash
# RP側コンテナ内でテスト
cd /path/to/sso-rp
docker-compose exec rp-app bash

# コンテナ内で実行
curl -k https://host.docker.internal:4443/health/ready
# 期待: {"status":"ok"} または Hydraヘルスチェックのレスポンス

# localhostとの違いを確認
curl -k https://localhost:4443/health/ready
# 期待: Connection refused または Timeout（コンテナ内にはポート4443がない）
```

**Step B: IdP側でクライアント再登録**

```bash
cd /path/to/sso-idp

# 既存クライアントの確認
docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445

# 必要に応じて既存クライアント削除
docker-compose exec hydra hydra delete oauth2-client <client-id> --endpoint http://localhost:4445

# 新規クライアント登録（localhost:4443 用）
./scripts/register-client.sh "https://localhost:3443/auth/callback" \
  --first-party \
  --cors-origin "https://localhost:4443,https://localhost:3443"

# 出力されたクライアントIDとシークレットをRP側に設定
```

**Step C: RP側に認証情報設定**

RP側の `.env.local`:
```bash
OAUTH_CLIENT_ID=<上記で取得したID>
OAUTH_CLIENT_SECRET=<上記で取得したシークレット>
```

**Step D: RP起動**

```bash
cd /path/to/sso-rp
docker-compose up -d
```

---

**📝 RP側の修正まとめ**

Phase 1への移行では、**sso-rp側も以下の修正が必須**です：

| 修正箇所 | 変更内容 | 理由 |
|---------|---------|------|
| `.env.local` | `OAUTH_TOKEN_URL` 等を<br>`host.docker.internal:4443` に | RPコンテナ内から IdP にアクセス |
| `docker-compose.yml` | `extra_hosts` 追加 | Linux環境での `host.docker.internal` サポート |
| SSL設定 | 証明書検証を無効化 | 自己署名証明書対応（開発環境のみ） |

**以前の構成（idp.localhost）との違い**:
```
以前: idp.localhost
  → extra_hosts: "idp.localhost:host-gateway"

Phase 1: localhost:4443
  → extra_hosts: "host.docker.internal:host-gateway"
  → URL を host.docker.internal に変更
```

**重要**: IdP側だけでなく、RP側も協調して修正しないと、Token Exchangeが失敗します。

---

#### 検証1-6: OAuth2フロー全体テスト 🔐 最重要

**シナリオ**: RP → IdP → 認証 → RP

**手順**:

1. **RPでSSOログイン開始**
   ```
   https://localhost:3443 → "Login with SSO" ボタン
   ```

2. **IdPにリダイレクト**
   ```
   https://localhost:4443/oauth2/auth?client_id=...&redirect_uri=...
   ```

   **ブラウザ開発者ツールで確認**:
   - Network タブを開く
   - リダイレクトチェーンを確認
   - すべてのURLが `https://localhost:4443` になっているか

3. **IdPログイン画面**
   ```
   https://localhost:4443/auth/login
   ```

   **確認ポイント**:
   - ✅ ログイン画面が表示される
   - ✅ URLが `https://localhost:4443/auth/login` になっている

4. **メール・パスワード入力**
   - テストユーザーでログイン

5. **2段階認証（有効な場合）**
   ```
   https://localhost:4443/auth/two_factor
   ```

   **確認ポイント**:
   - ✅ 2FAコード入力画面が表示される
   - ✅ セッションCookieが維持されている

6. **同意画面（first-partyの場合はスキップ）**

7. **RPにリダイレクト（コールバック）**
   ```
   https://localhost:3443/auth/callback?code=...&state=...
   ```

   **ブラウザ開発者ツールで確認**:
   - ✅ `code` パラメータが含まれている
   - ✅ `state` パラメータが含まれている
   - ✅ エラーメッセージがない

8. **RPでトークン交換**

   **Network タブで確認**:
   ```
   POST https://localhost:4443/oauth2/token
   Request Headers:
     Content-Type: application/x-www-form-urlencoded
   Request Body:
     grant_type=authorization_code
     code=...
     redirect_uri=https://localhost:3443/auth/callback
     client_id=...
     client_secret=...
   ```

   **期待するレスポンス**:
   ```json
   {
     "access_token": "...",
     "token_type": "bearer",
     "expires_in": 3600,
     "refresh_token": "...",
     "id_token": "..."
   }
   ```

9. **RPでユーザー情報取得**

   **Network タブで確認**:
   ```
   GET https://localhost:4443/userinfo
   Request Headers:
     Authorization: Bearer <access_token>
   ```

   **期待するレスポンス**:
   ```json
   {
     "sub": "user-id",
     "email": "test@example.com",
     "name": "Test User"
   }
   ```

10. **RPでログイン完了**
    ```
    https://localhost:3443/dashboard (例)
    ```

    **確認ポイント**:
    - ✅ ユーザー情報が表示される
    - ✅ RP側のセッションが確立されている

---

#### 検証1-7: CORS詳細確認 🌐

**ブラウザ開発者ツール（Network タブ）**:

**リクエスト1: Authorization**
```
Request URL: https://localhost:4443/oauth2/auth?...
Request Method: GET
Request Headers:
  Origin: https://localhost:3443  # RP側のオリジン

Response Headers:
  Access-Control-Allow-Origin: https://localhost:3443
  Access-Control-Allow-Credentials: true
```

**リクエスト2: Token Exchange**
```
Request URL: https://localhost:4443/oauth2/token
Request Method: POST
Request Headers:
  Origin: https://localhost:3443

Response Headers:
  Access-Control-Allow-Origin: https://localhost:3443
  Access-Control-Allow-Credentials: true
```

**リクエスト3: UserInfo**
```
Request URL: https://localhost:4443/userinfo
Request Method: GET
Request Headers:
  Origin: https://localhost:3443
  Authorization: Bearer <token>

Response Headers:
  Access-Control-Allow-Origin: https://localhost:3443
  Access-Control-Allow-Credentials: true
```

**検証ポイント**:
- ✅ すべてのリクエストで `Access-Control-Allow-Origin` が正しく返される
- ✅ `Access-Control-Allow-Credentials: true` が含まれる
- ✅ CORS エラーがコンソールに表示されない

**もしCORSエラーが発生する場合**:

コンソールエラー例:
```
Access to XMLHttpRequest at 'https://localhost:4443/oauth2/token' from origin 'https://localhost:3443' has been blocked by CORS policy
```

**確認箇所**:
1. Hydra設定（`docker/hydra/hydra.yml`）
2. クライアント登録時の `--cors-origin` オプション
3. Hydraログで CORS 関連エラーを確認

---

#### 検証1-8: Cookie Cross-Origin テスト 🍪🌐

**重要**: RP（`localhost:3443`）と IdP（`localhost:4443`）は**別オリジン**

**検証方法**:

1. **RPでSSOログイン → IdPでログイン完了**
2. **ブラウザで新しいタブを開く**
3. **直接IdPにアクセス**: `https://localhost:4443/`
4. **確認**: すでにログイン済み状態になっているか

**期待動作**:
- ✅ IdPのセッションCookieが維持されている
- ✅ 再度ログイン不要

**もしログアウト状態の場合**:
- ❌ Cookieの `SameSite` 設定が不適切
- ❌ Cookieの `Secure` 属性が付いていない

**デバッグ**:

ブラウザ開発者ツール → Application → Cookies:
```
Name: _idp_session
Value: <セッションID>
Domain: localhost
Path: /
Secure: ✓  # 必須
HttpOnly: ✓
SameSite: None  # Cross-Originで必要
```

---

### Phase 1の検証チェックリスト

実装後、以下をすべて確認：

- [ ] nginxコンテナが起動している
- [ ] `https://localhost:4443` でIdPにアクセスできる
- [ ] Hydraヘルスチェック (`/health/ready`) が成功
- [ ] Rails/Hydraへのリバースプロキシが動作
- [ ] **`X-Forwarded-Proto: https` が伝播している** ⭐
- [ ] **Cookie に `Secure` 属性が付与される** ⭐
- [ ] **Cookie の `SameSite` 設定が適切** ⭐
- [ ] **RP (`localhost:3443`) からのCORSリクエストが成功** ⭐
- [ ] **OAuth2フロー全体が動作する** ⭐
- [ ] Hydra内部のリダイレクトURLが正しい（`https://localhost:4443`）
- [ ] 2段階認証が動作する
- [ ] ログアウトが正常に動作する
- [ ] **Cross-Origin環境でCookieが維持される** ⭐

---

### Phase 1のトラブルシューティング

#### 問題1: Cookie に Secure属性が付かない

**確認箇所**:

1. **nginx設定**:
   ```nginx
   proxy_cookie_flags ~ secure;
   ```

2. **Rails設定**:
   ```ruby
   # config/initializers/session_store.rb
   Rails.application.config.session_store :cookie_store,
     key: '_idp_session',
     secure: true,  # 強制的にSecure属性を付与
     same_site: :none,
     httponly: true
   ```

3. **Rails force_ssl**:
   ```ruby
   # config/application.rb
   config.force_ssl = true
   ```

**デバッグ方法**:

```bash
# Railsログでセッション設定を確認
docker-compose logs web | grep session

# レスポンスヘッダーで確認
curl -k -i https://localhost:4443/auth/login | grep Set-Cookie
# 期待: Set-Cookie: _idp_session=...; path=/; secure; HttpOnly; SameSite=None
```

---

#### 問題2: CORSエラーが発生する

**エラー例**:
```
Access to XMLHttpRequest at 'https://localhost:4443/oauth2/token' from origin 'https://localhost:3443' has been blocked by CORS policy
```

**確認箇所**:

1. **Hydra設定（`docker/hydra/hydra.yml`）**:
   ```yaml
   serve:
     public:
       cors:
         enabled: true
         allowed_origins:
           - https://localhost:3443
         allowed_methods:
           - GET
           - POST
           - OPTIONS
         allowed_headers:
           - Authorization
           - Content-Type
         allow_credentials: true
   ```

2. **クライアント登録時のCORS設定**:
   ```bash
   ./scripts/register-client.sh "https://localhost:3443/auth/callback" \
     --first-party \
     --cors-origin "https://localhost:4443,https://localhost:3443"
   ```

3. **Hydraログで確認**:
   ```bash
   docker-compose logs hydra | grep CORS
   ```

**デバッグ方法**:

```bash
# プリフライトリクエスト（OPTIONS）の確認
curl -k -X OPTIONS https://localhost:4443/oauth2/token \
  -H "Origin: https://localhost:3443" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Content-Type" \
  -i

# 期待するレスポンスヘッダー:
# Access-Control-Allow-Origin: https://localhost:3443
# Access-Control-Allow-Methods: GET, POST, OPTIONS
# Access-Control-Allow-Credentials: true
```

---

#### 問題3: Hydraのリダイレクトが `http://` になる

**症状**:
- Hydraからのリダイレクトが `http://localhost:4443/...` になる

**原因**:
- `X-Forwarded-Proto: https` が伝わっていない

**確認方法**:

```bash
# HydraログでリダイレクトURLを確認
docker-compose logs hydra | grep redirect

# nginxの設定確認
docker-compose exec nginx cat /etc/nginx/nginx.conf | grep X-Forwarded-Proto
# 期待: proxy_set_header X-Forwarded-Proto https;
```

**修正方法**:

`docker/nginx/nginx.conf`:
```nginx
# すべてのlocationに適用されるよう、serverブロック直下に配置
server {
    listen 443 ssl http2;
    server_name localhost;

    # プロキシヘッダー設定（すべてのlocationで有効）
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port 443;

    location /oauth2/ {
        proxy_pass http://hydra:4444;
    }
    # ...
}
```

---

#### 問題4: OAuth2フローで "Request interrupted by user" エラー

**症状**:
- RP → IdP リダイレクト後、エラーが発生
- ブラウザコンソールに "Request interrupted" が表示

**原因**:
1. セッションCookieが送信されない（Secure属性の問題）
2. CSRF トークンが不一致（セッション維持の問題）
3. リダイレクトループ

**確認方法**:

1. **ブラウザ開発者ツール（Network タブ）**:
   - すべてのリクエストのステータスコードを確認
   - リダイレクトチェーンを追跡
   - Cookieが送信されているか確認

2. **Railsログ確認**:
   ```bash
   docker-compose logs web | grep -i "csrf"
   docker-compose logs web | grep -i "session"
   ```

3. **Hydraログ確認**:
   ```bash
   docker-compose logs hydra | grep -i "error"
   ```

**修正方法**:

1. **Cookieの `SameSite` 設定を修正**:
   ```ruby
   # config/initializers/session_store.rb
   Rails.application.config.session_store :cookie_store,
     key: '_idp_session',
     secure: true,
     same_site: :none,  # Cross-Originで必須
     httponly: true
   ```

2. **CSRF保護の設定確認**:
   ```ruby
   # app/controllers/application_controller.rb
   protect_from_forgery with: :exception, prepend: true
   ```

3. **Railsを再起動**:
   ```bash
   docker-compose restart web
   ```

---

### Phase 1完了条件

以下がすべて動作したら、**配布版として完成** ✅

Phase 2（証明書自動化）はオプションです：

✅ **基本動作**:
- nginxが正常に起動している
- `https://localhost:4443` でアクセスできる
- リバースプロキシが正常に動作している

✅ **プロキシヘッダー**:
- `X-Forwarded-Proto: https` が伝播している
- Rails/Hydraが HTTPS として認識している
- リダイレクトURLがすべて `https://` になっている

✅ **Cookie動作**:
- セッションCookieに `Secure` 属性が付いている
- `SameSite=None` が設定されている
- Cross-Origin環境でCookieが維持される

✅ **CORS動作**:
- RP → IdP のすべてのリクエストで CORS エラーが発生しない
- `Access-Control-Allow-Origin` が正しく返される

✅ **OAuth2フロー**:
- RP → IdP → 認証 → RP の全フローが成功
- トークン交換が成功する
- UserInfo取得が成功する
- エラーメッセージが表示されない

---

## 🚀 Phase 2: 証明書自動化（オプション）

### 目的

**Phase 1で主要目標は達成済み**。Phase 2は証明書管理を自動化したい場合のみ実施。

- Phase 1: 配布可能なIdP完成（/etc/hosts不要、`docker-compose up`で起動）
- Phase 2: 証明書の1年ごとの手動更新を自動化

### Phase 2の前提条件

⚠️ **Phase 1がすべて成功していること**

Phase 1で問題が残っている場合は、先に解決してから Phase 2 に進むこと。

---

**✅ RP側の変更は不要**

Phase 2（nginx → https-portal/Caddy）では、**sso-rp側の変更は一切不要**です：

- ✅ `.env.local` はそのまま（`host.docker.internal:4443` を継続使用）
- ✅ `docker-compose.yml` はそのまま
- ✅ SSL設定もそのまま

**理由**:
- IdP側のプロキシソフトウェア変更のみ
- 外部から見たURL（`https://localhost:4443`）は変わらない
- RP側はIdPの内部構成を知る必要がない（疎結合）

---

### Phase 2の選択肢

| 項目 | Phase 2-A: https-portal（推奨）⭐ | Phase 2-B: Caddy（参考） |
|-----|----------------------------------|------------------------|
| **nginx設定継承** | ✅ ほぼそのまま | ❌ 書き換え必要 |
| **動作確実性** | ✅ 高い | ⚠️ 検証必要 |
| **検証コスト** | 低い | 高い |
| **設定シンプル** | ⚠️ 中程度 | ✅ シンプル |

**詳細**: `idp-distribution-strategy.md` の Phase 2選択肢比較を参照

---

## Phase 2-A: https-portal への移行（推奨）⭐

### なぜhttps-portalを推奨するのか

- ✅ **現在のnginx.confをほぼそのまま使える** - 動作確認済みの設定を継承
- ✅ **動作の確実性が高い** - nginxベースで予測可能な挙動
- ✅ **検証コストが低い** - nginx知識・経験が活かせる
- ✅ **証明書自動生成** - `STAGE: local`で自己署名証明書を自動管理

### 実装手順（https-portal）

#### Step 2A-1: https-portal設定ファイルの作成

```bash
mkdir -p docker/https-portal
```

`docker/https-portal/localhost.conf.erb`:

```nginx
# 現在のnginx.confをほぼコピー（証明書パスのみ変数化）
server {
    listen 443 ssl http2;
    server_name localhost;

    # https-portalが自動生成する証明書を使用
    ssl_certificate <%= @ssl_certificate_path %>;
    ssl_certificate_key <%= @ssl_certificate_key_path %>;
    ssl_protocols TLSv1.2 TLSv1.3;

    # セキュリティヘッダー（変更なし）
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # プロキシヘッダー設定（変更なし - 重要！）
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Port 443;
    proxy_redirect off;
    proxy_cookie_flags ~ secure;  # 最重要

    # パスベースルーティング（変更なし）
    location /auth/ {
        proxy_pass http://web:3000;
    }

    location /oauth2/ {
        proxy_pass http://hydra:4444;
    }

    location /health/ {
        proxy_pass http://hydra:4444;
    }

    location /.well-known/ {
        proxy_pass http://hydra:4444;
    }

    location /userinfo {
        proxy_pass http://hydra:4444/userinfo;
    }

    location / {
        proxy_pass http://web:3000;
    }
}
```

**ポイント**: nginx.confから証明書パス以外をそのままコピー

---

#### Step 2A-2: docker-compose.yml の修正

**変更前（Phase 1）**:
```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "4443:443"
      - "8080:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/ssl:/etc/nginx/ssl:ro
```

**変更後（Phase 2-A）**:
```yaml
services:
  # nginx セクションをコメントアウト
  # nginx:
  #   ...

  # https-portal に置き換え
  https-portal:
    image: steveltn/https-portal:1
    ports:
      - "4443:443"
      - "8080:80"
    volumes:
      - ./docker/https-portal/localhost.conf.erb:/var/lib/nginx-conf/localhost.conf.erb:ro
    environment:
      STAGE: 'local'  # 自己署名証明書を自動生成
      DOMAINS: 'localhost'
    depends_on:
      - web
      - hydra
```

**注意**: 環境変数（.env）は変更なし（Phase 1と同じ）

---

#### Step 2A-3: 起動と確認

```bash
# コンテナ停止
docker-compose down

# https-portal起動
docker-compose up -d

# ログ確認
docker-compose logs -f https-portal
docker-compose logs -f web
docker-compose logs -f hydra

# 証明書自動生成確認
docker-compose exec https-portal ls -la /var/lib/https-portal/

# ヘルスチェック
curl -k https://localhost:4443/health/ready
```

---

### 検証手順（Phase 2-A）

**Phase 1と同じ検証を実施**:
- プロキシヘッダー伝播確認（HeaderLogger使用）
- Cookie Secure属性確認
- CORS動作確認
- OAuth2フロー全体テスト

**期待**: Phase 1と完全に同じ動作（nginx設定を継承しているため）

---

## Phase 2-B: Caddy への移行（参考）

### 注意事項

**Phase 2-Bは参考情報です**:
- ⚠️ プロキシヘッダー・Cookie設定の検証が必要
- ⚠️ nginx設定の書き換えが必要
- ⚠️ Hydra動作の再検証が必要

**推奨**: まずPhase 2-Aを試し、証明書自動化を達成してから、Caddyを検討

### 実装手順（Caddy）

#### Step 2B-1: Caddyfileの作成

```bash
mkdir -p docker/caddy
```

`docker/caddy/Caddyfile`:

```caddyfile
{
    # ローカル開発用の自己署名証明書を自動生成
    local_certs

    # ログレベル（開発時はDEBUG推奨）
    # debug
}

localhost:4443 {
    # パスベースルーティング（nginx.confと同じロジック）

    # IdP Rails アプリケーションの認証関連パス
    reverse_proxy /auth/* web:3000

    # Hydra Public API - OAuth2エンドポイント
    reverse_proxy /oauth2/* hydra:4444

    # Hydra ヘルスチェックエンドポイント
    reverse_proxy /health/* hydra:4444

    # Hydra の .well-known エンドポイント
    reverse_proxy /.well-known/* hydra:4444

    # Hydra UserInfo エンドポイント
    reverse_proxy /userinfo hydra:4444

    # IdP Rails アプリケーションのその他のパス
    reverse_proxy /* web:3000

    # セキュリティヘッダー
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"

    # Cookie Secure属性の自動付与（Caddy v2.7+）
    header Set-Cookie {
        +Secure
    }

    # ログ出力（検証時に有効化）
    # log {
    #     output stdout
    #     format console
    #     level DEBUG
    # }
}

# HTTPからHTTPSへのリダイレクト
http://localhost:8080 {
    redir https://localhost:4443{uri} permanent
}
```

**nginxとの対応表**:

| nginx | Caddy | 説明 |
|-------|-------|------|
| `server_name localhost;` | `localhost:4443 { ... }` | ホスト指定 |
| `location /auth/ { proxy_pass http://web:3000; }` | `reverse_proxy /auth/* web:3000` | パスルーティング |
| `proxy_set_header X-Forwarded-Proto https;` | 自動設定 | Caddyが自動で設定 |
| `proxy_cookie_flags ~ secure;` | `header Set-Cookie { +Secure }` | Cookie Secure属性 |
| `add_header Strict-Transport-Security ...` | `header Strict-Transport-Security ...` | HSTSヘッダー |
| `ssl_certificate ...` | `local_certs` | 証明書自動生成 |

---

#### Step 2-2: docker-compose.yml の修正

**変更前（Phase 1）**:
```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "4443:443"
      - "8080:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./docker/nginx/ssl:/etc/nginx/ssl:ro
    depends_on:
      - web
      - hydra
```

**変更後（Phase 2）**:
```yaml
services:
  # nginx セクションをコメントアウトまたは削除
  # nginx:
  #   image: nginx:alpine
  #   ...

  # Caddy に置き換え
  caddy:
    image: caddy:2-alpine
    ports:
      - "4443:443"   # ホストの4443 → コンテナの443
      - "8080:80"    # HTTP リダイレクト用
    volumes:
      - ./docker/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - web
      - hydra
    networks:
      - default

volumes:
  # 既存のvolumes...
  db-data:
  hydra-db-data:

  # Caddy用volume追加
  caddy-data:
  caddy-config:
```

**注意**: 環境変数（.env）は変更なし（Phase 1と同じ）

---

#### Step 2-3: 起動とログ確認

```bash
# コンテナ停止
docker-compose down

# nginx関連のvolumeは不要だが、データは保持
# （ロールバック用にnginx設定は残しておく）

# Caddy起動
docker-compose up -d

# ログ確認
docker-compose logs -f caddy
docker-compose logs -f web
docker-compose logs -f hydra

# Caddyの証明書生成確認
docker-compose exec caddy ls -la /data/caddy/certificates/local/

# 期待: localhost.crt, localhost.key が自動生成されている
```

---

### Phase 2の検証手順 🔍

**重要**: Phase 1と同じ検証を実施し、動作が維持されているか確認

#### 検証2-1: HTTPS接続

```bash
# ブラウザでアクセス
https://localhost:4443

# 期待: 自己署名証明書の警告（OK）
# 確認: IdPトップページが表示される（Phase 1と同じ）
```

---

#### 検証2-2: リバースプロキシ動作

```bash
# Rails へのルーティング
curl -k https://localhost:4443/
curl -k https://localhost:4443/auth/login

# Hydra へのルーティング
curl -k https://localhost:4443/oauth2/auth
curl -k https://localhost:4443/health/ready
curl -k https://localhost:4443/.well-known/openid-configuration
```

**期待**: Phase 1と同じレスポンス

---

#### 検証2-3: プロキシヘッダー伝播 ⭐

**確認方法**: Phase 1で追加した `HeaderLogger` を使用

```bash
# ブラウザで https://localhost:4443/ にアクセス

# ログ確認
docker-compose logs web | grep "Request Headers"
```

**期待される出力（Phase 1と同じ）**:
```
X-Forwarded-Proto: https
X-Forwarded-Host: localhost:4443
Host: localhost:4443
```

**もしヘッダーが異なる場合**:

Caddyfileに明示的に追加:
```caddyfile
localhost:4443 {
    reverse_proxy /auth/* web:3000 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }

    reverse_proxy /oauth2/* hydra:4444 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }

    # 他のlocationも同様
}
```

---

#### 検証2-4: Cookie動作 🍪

**Phase 1と同じ手順**:

1. `https://localhost:4443/auth/login` でログイン
2. **Application → Cookies → `https://localhost:4443`**
3. セッションCookieを確認:
   ```
   Name: _idp_session
   Secure: ✓
   SameSite: None
   ```

**期待**: Phase 1と同じCookie設定

**もし Secure属性が付いていない場合**:

1. **Caddyfileの確認**:
   ```caddyfile
   header Set-Cookie {
       +Secure
   }
   ```

2. **Caddyを再起動**:
   ```bash
   docker-compose restart caddy
   ```

---

#### 検証2-5: CORS動作 🌐

**Phase 1と同じ手順**:

1. RPからSSOログイン
2. **Network タブ**でCORSヘッダーを確認:
   ```
   Access-Control-Allow-Origin: https://localhost:3443
   Access-Control-Allow-Credentials: true
   ```

**期待**: Phase 1と同じCORSヘッダー

---

#### 検証2-6: OAuth2フロー全体 🔐

**Phase 1と同じシナリオ**:

1. RP → IdP → 認証 → RP
2. すべてのステップで正常動作
3. エラーが発生しない

**期待**: Phase 1と完全に同じ動作

---

### Phase 2の検証チェックリスト

Phase 1のチェックリストと同じ項目をすべて確認：

- [ ] Caddyコンテナが起動している
- [ ] `https://localhost:4443` でIdPにアクセスできる
- [ ] Hydraヘルスチェック (`/health/ready`) が成功
- [ ] Rails/Hydraへのリバースプロキシが動作
- [ ] **`X-Forwarded-Proto: https` が伝播している** ⭐
- [ ] **Cookie に `Secure` 属性が付与される** ⭐
- [ ] **Cookie の `SameSite` 設定が適切** ⭐
- [ ] **RP (`localhost:3443`) からのCORSリクエストが成功** ⭐
- [ ] **OAuth2フロー全体が動作する** ⭐
- [ ] Hydra内部のリダイレクトURLが正しい（`https://localhost:4443`）
- [ ] 2段階認証が動作する
- [ ] ログアウトが正常に動作する
- [ ] **Cross-Origin環境でCookieが維持される** ⭐
- [ ] **Caddy証明書が自動生成されている** ⭐

---

### Phase 2のトラブルシューティング

#### 問題1: Caddyが起動しない

```bash
# ログ確認
docker-compose logs caddy

# Caddyfile構文チェック
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# 一般的なエラー:
# - Caddyfile の構文エラー
# - ポートバインドエラー（nginxが残っている）
```

---

#### 問題2: プロキシヘッダーが Phase 1 と異なる

**デバッグ方法**:

```bash
# Caddyのリバースプロキシログを有効化
# Caddyfileに追加:
localhost:4443 {
    log {
        output stdout
        format console
        level DEBUG
    }

    reverse_proxy /auth/* web:3000 {
        # ヘッダーを明示的に設定
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-For {remote}
    }
}

# 再起動
docker-compose restart caddy

# ログ確認
docker-compose logs caddy | grep -i "forwarded"
```

---

#### 問題3: Cookie Secure属性が付かない

**確認手順**:

1. **Caddyfile確認**:
   ```caddyfile
   header Set-Cookie {
       +Secure
   }
   ```

2. **レスポンスヘッダー確認**:
   ```bash
   curl -k -i https://localhost:4443/auth/login | grep Set-Cookie
   ```

3. **Railsのセッション設定も確認**（Phase 1で設定済み）:
   ```ruby
   Rails.application.config.session_store :cookie_store,
     secure: true
   ```

---

#### 問題4: Phase 1 では動作したのに Phase 2 で動作しない

**比較デバッグ**:

1. **nginxに戻して動作確認**:
   ```bash
   # docker-compose.ymlでcaddyをコメントアウト、nginxを有効化
   docker-compose down
   docker-compose up -d

   # Phase 1の動作を再確認
   ```

2. **差分を特定**:
   - プロキシヘッダーの違い
   - Cookieヘッダーの違い
   - CORSヘッダーの違い

3. **Caddyfileに明示的な設定を追加**:
   ```caddyfile
   localhost:4443 {
       # nginxと同等の設定を明示
       reverse_proxy /auth/* web:3000 {
           header_up Host {host}
           header_up X-Real-IP {remote}
           header_up X-Forwarded-For {remote}
           header_up X-Forwarded-Proto {scheme}
           header_up X-Forwarded-Host {host}
           header_up X-Forwarded-Port {server_port}
       }

       # 他のlocationも同様
   }
   ```

---

### Phase 2完了条件

Phase 1の完了条件に加えて：

✅ **Caddy特有の動作**:
- Caddy証明書が自動生成されている
- 証明書の有効期限管理が不要
- Caddyfileがシンプルで保守しやすい

✅ **Phase 1との動作一致**:
- すべての検証項目が Phase 1 と同じ結果
- パフォーマンスに大きな差がない
- エラーログに問題がない

---

## 🔄 ロールバック手順

### Phase 1 でロールバック（検証版に戻す）

```bash
# docker-compose.yml を元に戻す
git checkout docker-compose.yml

# nginx.conf を元に戻す
git checkout docker/nginx/nginx.conf

# SSL証明書を元に戻す
cd docker/nginx/ssl
mv localhost.crt.backup localhost.crt
mv localhost.key.backup localhost.key

# 環境変数を元に戻す
# .env
HOST_NAME=idp.localhost
HOST_PORT=443
HYDRA_PUBLIC_URL=https://idp.localhost

# 再起動
docker-compose down
docker-compose up -d

# /etc/hosts を元に戻す
sudo sh -c 'echo "127.0.0.1 idp.localhost" >> /etc/hosts'
```

---

### Phase 2 でロールバック（Phase 1に戻す）

```bash
# docker-compose.yml でcaddyをコメントアウト、nginxを有効化
# 編集: docker-compose.yml

# 再起動
docker-compose down
docker-compose up -d

# nginx設定はそのまま（Phase 1の設定）
# 環境変数もそのまま（Phase 1の設定）
```

---

## 📝 次のステップ（Phase 2完了後）

1. **ヘッダーロギング削除**:
   ```ruby
   # config/application.rb から HeaderLogger を削除
   git checkout config/application.rb
   ```

2. **ドキュメント更新**:
   - README.md: クイックスタート手順を `https://localhost:4443` に更新
   - INTEGRATION.md: `/etc/hosts` 設定手順を削除

3. **スクリプト更新**:
   - `scripts/register-client.sh`: デフォルトCORS設定を更新

4. **nginx設定の保管**:
   ```bash
   # 将来の参考用にnginx設定を保管
   mkdir -p docs/legacy
   mv docker/nginx docs/legacy/nginx-backup
   ```

5. **GitHub公開**:
   - sso-idp リポジトリに反映
   - sso-rp と連携テスト

---

## 📊 まとめ

### Phase 1（nginx + localhost:4443）

**目的**: ドメイン/ポート変更の影響を検証
**期間**: 1-2日
**重点**: Cookie、CORS、OAuth2フロー
**RP側の対応**: ✅ **必要** - `.env.local` と `docker-compose.yml` を修正

### Phase 2（証明書自動化、オプション）

**目的**: 証明書管理の自動化（Phase 1で主要目標は達成済み）
**期間**: 0.5-1日
**推奨**: Phase 2-A（https-portal） - nginx設定継承、動作確実性
**参考**: Phase 2-B（Caddy） - 設定シンプル、検証必要
**RP側の対応**: ❌ **不要** - Phase 1の設定をそのまま使用

### メリット

- ✅ 問題の切り分けが容易（Phase分離）
- ✅ 各ステップでロールバック可能
- ✅ Cookie/CORS問題を段階的に解決
- ✅ Phase 1で配布版として完成
- ✅ Phase 2はオプション（証明書自動化のみ）
- ✅ Phase 2-Aなら動作確実性が高い

### ⚠️ 注意点

**sso-idp単体では完結しない**:
- Phase 1では **sso-rp側も協調修正が必須**
- RPコンテナ内アクセスのため `host.docker.internal` 設定が必要
- IdP/RP両方のリポジトリで作業が必要

---

**作成日**: 2025-10-22
**対象**: sso-idp リポジトリでの段階的Caddy移行
**前提ドキュメント**: nginx-configuration.md, idp-distribution-strategy.md
