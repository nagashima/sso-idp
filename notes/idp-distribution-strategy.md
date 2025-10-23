# IdP提供戦略 - 検証版から配布版への移行

## 📋 現状の整理

### 検証版（現在）

**目的**: ORY Hydraの動作検証（CORS、HTTPS、Cookie）

**構成**:
```
idp/ (https://idp.localhost)
  └── nginx + Rails IdP + Hydra

rp/ (https://localhost:3443)
  └── 検証用RPアプリ
```

**特徴**:
- IdPが主役、RPは動作確認用
- 別ドメインでCross-Origin検証
- `/etc/hosts` 設定必要
- AWS ECS運用を想定した構成

---

### 配布版（目標）

**目的**: RP開発者が簡単にSSO統合できる

**要件**:
- RPが主役、IdPは疎結合に提供
- `docker-compose up` だけで動作
- `/etc/hosts` 設定不要が望ましい
- SSL証明書管理が自動化されている
- 既存RPプロジェクトに影響を与えない

**利用シーン**:
```
RP開発者の環境:

sso-idp/          # git clone して起動
my-rp-app/        # 既存RPプロジェクト（独立）
other-rp/         # 別のRPプロジェクト（独立）
```

---

## 🎯 2つの検討軸

### 検討点1: ドメイン・ポート設定 ⭐ **最重要**

IdPへのアクセス方法をどうするか。

#### パターンA: `idp.localhost` (現状)

```
IdP: https://idp.localhost (port 443)
RP:  https://localhost:3443
```

**メリット**:
- ✅ 分かりやすいホスト名
- ✅ 検証版の設定・動作をそのまま継承

**デメリット**:
- ❌ `/etc/hosts` 設定が必要
  ```bash
  sudo sh -c 'echo "127.0.0.1 idp.localhost" >> /etc/hosts'
  ```
- ⚠️ Windows/Mac/Linuxで手順が異なる

---

#### パターンE: `localhost:4443` ⭐ 推奨

```
IdP: https://localhost:4443
RP:  https://localhost:3443
```

**メリット**:
- ✅ `/etc/hosts` 設定不要
- ✅ `docker-compose up` だけで完結
- ✅ ポート違い = 別オリジン（CORS動作維持）

**デメリット・検証事項**:
- ⚠️ URL末尾にポート番号（`:4443`）
- ⚠️ **プロキシ設定がそのまま継承できるか検証必要**
- ⚠️ **Cookie動作が別ドメイン環境と同じか検証必要**

**Same Origin Policyの確認**:
```
Origin = スキーム + ホスト + ポート

https://localhost:4443 (IdP)
https://localhost:3443 (RP)
→ ポートが異なる = 別オリジン = CORS必要
```

**ポートによるDocker領域の振り分け**:
```
ブラウザ → https://localhost:4443
   ↓
ホストOS (ポート4443)
   ↓
IdP docker-compose → caddy/nginx → Rails/Hydra

ブラウザ → https://localhost:3443
   ↓
ホストOS (ポート3443)
   ↓
RP docker-compose → RPアプリ
```

ポート番号でホストOSが振り分けるため、完全に独立したdocker-compose領域として動作。

---

### 検討点2: リバースプロキシ（nginx vs Caddy）

SSL証明書管理とプロキシ設定の維持。

#### オプションA: nginx継続

**必要な変更**:
```bash
# 証明書の再生成（CN変更）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout localhost.key \
  -out localhost.crt \
  -subj "/CN=localhost"
```

```yaml
# docker-compose.yml
nginx:
  ports:
    - "4443:443"  # ポート変更
```

```nginx
# nginx.conf
server {
    server_name localhost;  # idp.localhost → localhost
    # 既存のプロキシ設定はそのまま
}
```

**メリット**:
- ✅ 既存のプロキシ設定をそのまま使用
- ✅ 動作確認済みの設定を維持

**デメリット**:
- ❌ 証明書の有効期限管理（1年ごとに再生成）
- ⚠️ GitHub上の証明書も定期更新必要

---

#### オプションB: Caddy移行 ⭐ 推奨

**構成**:

```yaml
# docker-compose.yml
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "4443:443"
      - "8080:80"
    volumes:
      - ./docker/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config

volumes:
  caddy-data:
  caddy-config:
```

```caddyfile
# docker/caddy/Caddyfile
{
    local_certs  # 起動時に自己署名証明書を自動生成
}

localhost:4443 {
    # パスベースルーティング
    reverse_proxy /auth/* web:3000
    reverse_proxy /oauth2/* hydra:4444
    reverse_proxy /health/* hydra:4444
    reverse_proxy /.well-known/* hydra:4444
    reverse_proxy /userinfo hydra:4444
    reverse_proxy /* web:3000

    # セキュリティヘッダー
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
}
```

**メリット**:
- ✅ 証明書の完全自動管理（期限切れ問題なし）
- ✅ 設定がシンプル（nginx.conf 58行 → Caddyfile 約20行）
- ✅ プロキシヘッダー（`X-Forwarded-Proto`等）自動設定

**デメリット・検証事項**:
- ⚠️ **プロキシヘッダー設定が検証版と同等か確認必要**
- ⚠️ **Cookie Secure属性の自動付与を検証必要**
- ⚠️ Caddyの学習コスト（ただし低い）

**Caddyのプロキシヘッダーデフォルト動作**:

Caddyは以下を自動設定：
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- `X-Forwarded-Host`

nginxの`proxy_cookie_flags ~ secure`相当:
```caddyfile
# Caddy v2.7+
header Set-Cookie {
    +Secure
}
```

---

## 📊 パターン組み合わせマトリックス

| 提供パターン | nginx | Caddy |
|------------|-------|-------|
| **A: idp.localhost** | 現状 | 可能 |
| **E: localhost:4443** | 可能 | **推奨** ⭐ |

### 各パターンの評価

#### A × nginx（現状維持）
- ✅ 動作確認済み
- ❌ `/etc/hosts` 設定必要
- ❌ 証明書期限管理

#### A × Caddy
- ✅ 証明書自動
- ❌ `/etc/hosts` 設定必要
- ⚠️ 移行コスト
- 💭 メリット少ない

#### E × nginx
- ✅ `/etc/hosts` 不要
- ✅ 既存プロキシ設定流用
- ❌ 証明書再生成 + 期限管理

#### **E × Caddy** ⭐⭐⭐ 最推奨
- ✅ `/etc/hosts` 不要
- ✅ 証明書自動
- ✅ 設定シンプル
- ⚠️ **プロキシ設定・Hydra動作の継承を検証必要**

---

## ⚠️ 最重要検証ポイント（検討点1）

### なぜ検討点1が重要か

**検証版で動作している設定が、localhost統一環境でも同じように動作するか**を確認する必要がある。

#### 検証項目

1. **プロキシヘッダーの動作**
   ```
   nginx/Caddy → Rails/Hydra
   X-Forwarded-Proto: https
   X-Forwarded-Port: 4443
   Host: localhost
   ```

   Rails/Hydraが正しくHTTPS認識するか：
   ```ruby
   request.protocol  # => "https://"
   request.ssl?      # => true
   url_for(...)      # => "https://localhost:4443/..."
   ```

2. **Cookie動作（別ドメイン相当）**

   **シナリオ**:
   ```
   RP (localhost:3443) → IdP (localhost:4443)
   ```

   **検証項目**:
   - `SameSite=None; Secure` の動作
   - Cross-Originでのクッキー送受信
   - セッション維持

   **ブラウザ開発者ツールで確認**:
   ```
   Application → Cookies → https://localhost:4443
   → Secure: ✓
   → SameSite: None
   ```

3. **CORS動作**

   RPからIdPへのリクエストで：
   ```
   Request Headers:
     Origin: https://localhost:3443

   Response Headers:
     Access-Control-Allow-Origin: https://localhost:3443
     Access-Control-Allow-Credentials: true
   ```

4. **OAuth2フロー全体**

   ```
   1. RP → IdP Authorization
      https://localhost:4443/oauth2/auth?...

   2. IdPで認証

   3. IdP → RP Callback
      https://localhost:3443/auth/callback?code=...

   4. RP → IdP Token Exchange
      https://localhost:4443/oauth2/token
   ```

   全ステップでHTTPS、Cookie、リダイレクトが正常動作するか。

5. **Hydra内部動作**

   - Hydraが生成するリダイレクトURLが `https://localhost:4443` になるか
   - Hydra JWKs エンドポイントが正常動作するか
   - Consent/Login フローが正常動作するか

---

## 🚀 推奨実装フロー（段階的アプローチ）

### Phase 1: localhost:4443 + nginx（必須）

**目的**: ドメイン/ポート変更の影響を検証

**実装内容**:
1. SSL証明書再生成（CN=localhost）
2. nginx.conf 修正（server_name localhost、ポート設定）
3. docker-compose.yml 修正（ポート `4443:443`）
4. .env 修正（`HOST_NAME=localhost`, `HOST_PORT=4443`）

**メリット**:
- ✅ `/etc/hosts` 設定不要
- ✅ 動作確認済みのnginx設定を継続
- ✅ 主要目標達成（配布しやすいIdP）

**デメリット**:
- ⚠️ 証明書手動管理（1年ごとに再生成）

---

### Phase 2: 証明書自動化（オプション）

**Phase 1で主要目標は達成済み**。Phase 2は証明書管理を自動化したい場合のみ実施。

#### Phase 2の選択肢比較

| 項目 | https-portal（推奨）⭐ | Caddy |
|-----|----------------------|-------|
| **ベース** | nginx | 独自（Go製） |
| **現在のnginx設定継承** | ✅ ほぼそのまま使える | ❌ 書き換え必要 |
| **動作の確実性** | ✅ 高い（nginxベース） | ⚠️ 検証必要 |
| **証明書自動生成** | `STAGE: local` | `local_certs` |
| **設定方法** | 環境変数 + カスタムnginx設定 | Caddyfile |
| **nginx知識の活用** | ✅ そのまま活かせる | ❌ 新規学習 |
| **検証コスト** | 低い | 高い |
| **設定のシンプルさ** | ⚠️ カスタム設定必要 | ✅ Caddyfile 20行 |

---

#### Phase 2-A: https-portal への移行（推奨）⭐

**なぜ推奨か**:
- ✅ **現在のnginx.confをほぼそのまま使える**
- ✅ **動作確認済みの設定を継承**
- ✅ **nginx知識・経験が活かせる**
- ✅ **検証コストが低い**

**設定イメージ**:
```yaml
# docker-compose.yml
services:
  https-portal:
    image: steveltn/https-portal:1
    ports:
      - "4443:443"
    volumes:
      - ./docker/https-portal/localhost.conf.erb:/var/lib/nginx-conf/localhost.conf.erb:ro
    environment:
      STAGE: 'local'  # 自己署名証明書自動生成
      DOMAINS: 'localhost'
```

```nginx
# localhost.conf.erb（現在のnginx.confをほぼコピー）
server {
    listen 443 ssl http2;
    server_name localhost;

    # https-portalが自動生成する証明書
    ssl_certificate <%= @ssl_certificate_path %>;
    ssl_certificate_key <%= @ssl_certificate_key_path %>;

    # 既存の設定をそのまま
    proxy_set_header X-Forwarded-Proto https;
    proxy_cookie_flags ~ secure;  # 重要！

    location /auth/ {
        proxy_pass http://web:3000;
    }
    # ... 以下同じ
}
```

**詳細**: `migration-guide.md` の Phase 2-A を参照

---

#### Phase 2-B: Caddy への移行（参考）

**特徴**:
- ✅ **設定がシンプル**（Caddyfile 約20行）
- ✅ **証明書完全自動管理**
- ⚠️ **プロキシヘッダー・Cookie設定の検証が必要**

**設定イメージ**:
```caddyfile
{
    local_certs  # 自己署名証明書自動生成
}

localhost:4443 {
    reverse_proxy /auth/* web:3000
    reverse_proxy /oauth2/* hydra:4444
    # ...

    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header Set-Cookie {
        +Secure
    }
}
```

**注意点**:
- nginx設定の書き換えが必要
- プロキシヘッダーの動作確認が必須
- Cookie Secure属性の自動付与を検証

**詳細**: `migration-guide.md` の Phase 2-B を参照

---

## 📝 まとめ

### 現状（検証版）
- IdP: `https://idp.localhost` (nginx)
- RP: `https://localhost:3443`
- `/etc/hosts` 設定必要
- 証明書共有（期限管理必要）

### 配布版（Phase 1実装）
- IdP: `https://localhost:4443` (nginx)
- RP: `https://localhost:3443`
- `/etc/hosts` 設定不要 ✅
- 証明書手動管理（1年ごと）⚠️

### 配布版+証明書自動化（Phase 2実装、オプション）
- IdP: `https://localhost:4443` (https-portal 推奨 / Caddy 参考)
- RP: `https://localhost:3443`
- `/etc/hosts` 設定不要 ✅
- 証明書自動生成 ✅

### 推奨アプローチ

1. **Phase 1を必ず実装** - 主要目標を達成
2. **Phase 2はオプション** - 証明書自動化が必要な場合のみ
3. **Phase 2ではhttps-portalを推奨** - nginx設定継承、動作確実性

---

**作成日**: 2025-10-22
**対象環境**: Rails 8.0 + ORY Hydra v2.3.0
