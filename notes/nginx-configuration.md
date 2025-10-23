# nginx構成の設計意図と存在意義

## 📋 目次

1. [概要](#概要)
2. [nginx構成の目的](#nginx構成の目的)
3. [nginx構成の全体像](#nginx構成の全体像)
4. [nginx.conf設定の詳細解説](#nginxconf設定の詳細解説)
5. [検証できるポイント](#検証できるポイント)

---

## 概要

本プロジェクトでは、Rails IdP + ORY Hydra の前段にnginxをHTTPS終端・リバースプロキシとして配置しています。

```
[Browser]
   ↓ HTTPS (443)
[nginx] ← HTTPS終端・リバースプロキシ
   ↓ HTTP (内部通信)
   ├─ Rails IdP (web:3000)
   └─ Hydra OAuth2 (hydra:4444)
```

**重要**: この構成は単なる開発環境の利便性のためではなく、**本番環境（AWS ECS）運用を想定した検証環境**として設計されています。

---

## nginx構成の目的

### 1. **AWS ECS運用の再現**

本番環境では以下の構成を想定：

```
Internet
   ↓
ALB (Application Load Balancer)
   ↓ HTTPS終端
ECS Service
   ├─ Rails IdP Task
   └─ Hydra Task
```

開発環境でこれを再現：

```
Browser
   ↓
nginx (ALB相当)
   ↓ HTTPS終端
Docker Compose Services
   ├─ web (Rails IdP)
   └─ hydra (Hydra)
```

### 2. **リバースプロキシ時の挙動検証**

以下の重要な動作を開発環境で検証するため：

#### a) Cookie挙動の検証
- Cross-Domain環境でのCookie送受信
- `SameSite=None; Secure` 属性の動作確認
- `proxy_cookie_flags` によるSecure属性の自動付与

#### b) HTTPS状況下の動作確認
- `X-Forwarded-Proto: https` ヘッダーの伝播
- Rails/HydraがHTTPSとして正しく認識
- リダイレクトURL生成（`http://` ではなく `https://`）

#### c) CORS (Cross-Origin Resource Sharing)
- RP（`https://localhost:3443`）からIdP（`https://idp.localhost`）へのクロスオリジン通信
- 別ドメイン間でのOAuth2フロー

### 3. **別ドメイン運用の再現**

- IdP: `https://idp.localhost`
- RP: `https://localhost:3443`

本番環境での異なるドメイン間SSO連携を再現し、以下を検証：
- Cross-Origin Cookie
- CSRF対策
- リダイレクトURI検証

### 4. **パスベースルーティングの検証**

1つのドメイン（`idp.localhost`）配下で、複数のバックエンド（Rails、Hydra）へのルーティング：

```
https://idp.localhost/auth/*      → Rails IdP
https://idp.localhost/oauth2/*    → Hydra
https://idp.localhost/.well-known/* → Hydra
https://idp.localhost/*           → Rails IdP
```

これはマイクロサービス構成での一般的なパターンであり、本番運用での挙動を再現。

---

## nginx構成の全体像

### ディレクトリ構造

```
docker/nginx/
├── nginx.conf           # nginx設定ファイル
└── ssl/
    ├── localhost.crt    # 自己署名証明書
    └── localhost.key    # 秘密鍵
```

### Docker Compose構成

```yaml
nginx:
  image: nginx:alpine
  ports:
    - "443:443"  # HTTPS
    - "80:80"    # HTTP→HTTPS リダイレクト
  volumes:
    - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./docker/nginx/ssl:/etc/nginx/ssl:ro
  depends_on:
    - web
    - hydra
```

---

## nginx.conf設定の詳細解説

### 全体構成

```nginx
# HTTPからHTTPSへのリダイレクト
server {
    listen 80;
    server_name idp.localhost;
    return 301 https://$server_name$request_uri;
}

# HTTPS設定
server {
    listen 443 ssl http2;
    server_name idp.localhost;

    # SSL証明書設定
    # 共通proxy設定
    # パスベースルーティング
}
```

### 1. SSL/TLS設定

```nginx
ssl_certificate /etc/nginx/ssl/localhost.crt;
ssl_certificate_key /etc/nginx/ssl/localhost.key;
ssl_protocols TLSv1.2 TLSv1.3;
```

**意図**:
- 開発環境での自己署名証明書使用
- 本番相当のTLSプロトコル設定
- TLS 1.2/1.3のみ許可（セキュリティベストプラクティス）

### 2. セキュリティヘッダー

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

**意図**:
- HSTS (HTTP Strict Transport Security) の有効化
- ブラウザに常にHTTPS接続を強制
- 本番環境と同等のセキュリティ設定

### 3. プロキシヘッダー設定（最重要）

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Port 443;
proxy_redirect off;
proxy_cookie_flags ~ secure;
```

#### 各ヘッダーの意義

| ヘッダー | 値 | 目的 |
|---------|-----|------|
| `Host` | `idp.localhost` | オリジナルのホスト名をバックエンドに伝達 |
| `X-Real-IP` | クライアントIP | アクセス元IPの記録（ログ・セキュリティ） |
| `X-Forwarded-For` | クライアントIP | プロキシチェーン全体のIP記録 |
| `X-Forwarded-Proto` | `https` | **最重要**: バックエンドにHTTPS接続であることを伝達 |
| `X-Forwarded-Port` | `443` | 元のポート番号を伝達 |

#### `X-Forwarded-Proto: https` の重要性

**なぜ必要か？**

nginxとバックエンド（Rails/Hydra）間の通信は **HTTP** です：

```
Browser --(HTTPS)--> nginx --(HTTP)--> Rails/Hydra
```

このヘッダーがないと：
- Rails/Hydraは「HTTP接続」と認識
- リダイレクトURL生成時に `http://idp.localhost/...` を生成してしまう
- Cookieの `Secure` 属性が正しく動作しない
- CSRF対策が機能しない

このヘッダーがあると：
- Rails/Hydraは「元の接続はHTTPS」と認識
- 正しく `https://idp.localhost/...` でURLを生成
- Cookieに `Secure` 属性を付与
- **本番環境（ALB + ECS）と同じ挙動を再現**

#### `proxy_cookie_flags ~ secure;`

**意図**:
- バックエンドから返されるすべてのCookieに `Secure` 属性を自動付与
- HTTPS環境でのみCookieが送信されることを保証
- Cross-Origin環境での `SameSite=None; Secure` 動作検証

### 4. パスベースルーティング

```nginx
# IdP Rails アプリケーションの認証関連パス (port 3000)
location /auth/ {
    proxy_pass http://web:3000;
}

# Hydra Public API - OAuth2エンドポイント (port 4444)
location /oauth2/ {
    proxy_pass http://hydra:4444;
}

# Hydra ヘルスチェックエンドポイント
location /health/ {
    proxy_pass http://hydra:4444;
}

# Hydra の .well-known エンドポイント
location /.well-known/ {
    proxy_pass http://hydra:4444;
}

# Hydra UserInfo エンドポイント
location /userinfo {
    proxy_pass http://hydra:4444/userinfo;
}

# IdP Rails アプリケーションのその他のパス (port 3000)
location / {
    proxy_pass http://web:3000;
}
```

#### ルーティング設計の意図

| パス | バックエンド | 理由 |
|-----|-------------|------|
| `/auth/*` | Rails IdP | ログイン・同意画面など認証UI |
| `/oauth2/*` | Hydra | OAuth2標準エンドポイント (authorize, token, etc.) |
| `/health/*` | Hydra | Hydraヘルスチェック（ELB向け） |
| `/.well-known/*` | Hydra | OIDC Discovery metadata |
| `/userinfo` | Hydra | OAuth2 UserInfo endpoint |
| `/*` | Rails IdP | その他すべて（トップページ、管理画面など） |

**マイクロサービスパターンの再現**:
- 1つのドメインで複数サービスを公開
- パスでサービスを振り分け
- AWS ECSでの一般的な構成

---

## 検証できるポイント

### 1. Cookie挙動の検証

#### Cross-Domain Cookie

**シナリオ**:
1. RP (`https://localhost:3443`) からIdP (`https://idp.localhost`) にリダイレクト
2. IdPでログイン → セッションCookie発行
3. RPに戻る → IdPのCookieが正しく維持されているか

**検証項目**:
- `SameSite=None; Secure` の動作
- Cross-Originでのクッキー送信
- `proxy_cookie_flags ~ secure` の効果

#### ブラウザ開発者ツールでの確認

```
Application → Cookies → https://idp.localhost
→ Secure: ✓
→ SameSite: None
```

### 2. HTTPS認識の検証

#### Rails側での確認

```ruby
# Railsコンソールで確認
request.protocol  # => "https://"
request.ssl?      # => true
url_for(controller: 'auth', action: 'login')
# => "https://idp.localhost/auth/login"  (http:// ではない)
```

#### Hydra側での確認

```bash
# OAuth2 Authorize URLの生成
curl -k https://idp.localhost/oauth2/auth?...
# → リダイレクト先が https://idp.localhost/auth/login になる
```

### 3. CORS動作の検証

#### ブラウザ開発者ツールでの確認

```
Network → Headers
Request Headers:
  Origin: https://localhost:3443
Response Headers:
  Access-Control-Allow-Origin: https://localhost:3443
  Access-Control-Allow-Credentials: true
```

### 4. リバースプロキシヘッダー伝播の検証

#### Railsログでの確認

```ruby
# config/application.rb または middleware設定
Rails.application.config.middleware.insert_before 0, Rack::LogHeaders

# ログ出力例
X-Forwarded-Proto: https
X-Forwarded-Port: 443
Host: idp.localhost
```

### 5. OAuth2フロー全体の検証

**フロー**:
```
1. RP → IdP Authorization Request
   https://idp.localhost/oauth2/auth?...

2. nginx → Hydra (hydra:4444)
   Hydra → Rails (web:3000) ← ログイン画面表示要求

3. ユーザーログイン → Rails → Hydra

4. Hydra → RP (callback)
   https://localhost:3443/auth/callback?code=...
```

**検証項目**:
- すべてのリダイレクトが `https://` で生成される
- Cookieが各ステップで正しく維持される
- Cross-Originでも動作する

---

## まとめ

### 現在のnginx構成は以下を目的としています

1. ✅ **AWS ECS本番環境の再現**
   - ALB（HTTPS終端） + ECSタスク（HTTP）の構成を再現

2. ✅ **リバースプロキシ時の挙動検証**
   - `X-Forwarded-Proto` ヘッダーの動作確認
   - Cookie（Secure属性）の動作確認
   - HTTPS状況下でのURL生成確認

3. ✅ **Cross-Domain SSO検証**
   - 別ドメイン（IdP/RP）間でのOAuth2フロー
   - CORS設定の動作確認

4. ✅ **パスベースルーティング検証**
   - マイクロサービス構成の再現
   - Rails/Hydra間のパス振り分け

---

**作成日**: 2025-10-22
**対象環境**: Rails 8.0 + ORY Hydra v2.3.0 + nginx
