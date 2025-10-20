# Rails 8.0 SSO Identity Provider (IdP) - HTTPS対応版

**ORY Hydra v2.3.0**を活用したSSO認証システムのIdentity Provider

## 🚀 クイックスタート

### 初回セットアップ
```bash
# 1. リポジトリのクローン
git clone [repository]
cd sso-idp

# 2. /etc/hosts設定（macOS/Linux）
sudo sh -c 'echo "127.0.0.1 idp.localhost" >> /etc/hosts'

# 3. 起動（初回は自動ビルド＋DB初期化）
docker-compose up -d
```

### 動作確認
- **IdP認証画面**: https://idp.localhost

### 日常開発
```bash
docker-compose up -d      # 起動
docker-compose down       # 停止
docker-compose logs -f    # ログ確認
```

---

## 🏗️ アーキテクチャ

### サービス構成
```
                    外部RP
           ┌─────────────────────┐
           │  External RP Apps   │
           │ (完全に独立した環境)   │
           └──────────┬──────────┘
                      │ HTTPS / OAuth2 requests
                      ▼
           ┌─────────────────────┐
           │       nginx         │
           │      (HTTPS)        │
           │     (port 443)      │
           └──────────┬──────────┘
                      │ リバースプロキシ
                      ▼
    ┌─────────────────┐    ┌─────────────────┐
    │      Rails      │    │      Hydra      │
    │       IdP       │◄──►│  OAuth2 Server  │
    │    (内部:3000)   │    │   (内部:4444)   │
    └─────┬─────┬─────┘    └─────────┬───────┘
          │     └────────────────────┤
          ▼   　　　　　　　　　　　　　　▼
    ┌─────────────────┐    ┌─────────────────┐
    │     Valkey      │    │      MySQL      │
    │  Session/Cache  │    │     Database    │
    │   (内部:6379)    │    │   (内部:3306)   │
    │    Rails専用     │    │ Rails+Hydra共用 │
    └─────────────────┘    └─────────────────┘
```

### 認証フロー
1. **基本WEBログイン**: メール+パスワード → 認証コード（2段階認証）
2. **OAuth2/SSO**: 外部RP → nginx → IdP認証 → 同意画面 → RPへリダイレクト
3. **グローバルログアウト**: 全RPセッション一括クリア

---

## 🔧 設定

### 環境変数（`.env`）
`.env`ファイルには開発用のデフォルト設定が含まれています。主な設定項目：

```bash
# HTTPS環境設定
HOST_NAME=idp.localhost
HOST_PORT=443
HYDRA_PUBLIC_URL=https://idp.localhost

# ログアウト戦略
LOGOUT_STRATEGY=local  # or 'global'
```

**注意**: 本番環境では、データベースパスワード、JWT秘密鍵、SSL証明書などを適切に変更してください。

## 🔑 OAuth2クライアント管理

### RPクライアント登録

#### **登録**
```bash
# 外部RPクライアント（同意画面あり）
./scripts/register-client.sh "https://your-rp-domain.com/auth/callback"

# 信頼クライアント（同意画面スキップ）
./scripts/register-client.sh "https://your-rp-domain.com/auth/callback" --first-party

# CORS対応クライアント
./scripts/register-client.sh "https://your-rp-domain.com/auth/callback" \
  --cors-origins "https://your-rp-domain.com,https://app.example.com"
```

#### **登録例（ローカル開発環境）**
RPが `https://localhost:3443` で動作している場合：
```bash
./scripts/register-client.sh "https://localhost:3443/auth/sso/callback" \
  --first-party \
  --cors-origin "https://idp.localhost,https://localhost:3443"
```

#### **登録結果の確認**
```bash
# 登録済みクライアント一覧
docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445

# 特定クライアントの詳細確認
docker-compose exec hydra hydra get oauth2-client CLIENT_ID --endpoint http://localhost:4445 --format json
```

---

## 📝 開発コマンド

### Docker操作
```bash
# サービス起動
docker-compose up -d

# サービス停止
docker-compose down

# ログ確認
docker-compose logs -f [service_name]

# コンテナ内シェル
docker-compose exec web bash
```

### Rails操作
```bash
# コンソール
docker-compose exec web bundle exec rails console

# マイグレーション
docker-compose exec web bundle exec rails db:migrate

# データベースリセット
docker-compose exec web bundle exec rails db:reset

# テスト実行
docker-compose exec web bundle exec rspec

# その他のRailsコマンド
docker-compose exec web bundle exec rails [command]
```

**注意**: Railsはwebコンテナにクリーンインストールされており、ホスト上では動作しません。webコンテナ上では必ず`bundle exec`を付けて実行してください。

### DB操作
```bash
# MySQL接続
docker-compose exec db mysql -u rails idp_development -prails_password
```

### Hydra操作
```bash
# クライアント一覧
docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445

# 健全性チェック
curl -k https://idp.localhost/health/ready

# Hydraセッション確認（開発用）
docker-compose exec db mysql -u rails hydra_development -prails_password -e \
  "SELECT subject, client_id, remember, remember_for FROM hydra_oauth2_consent_request_handled ORDER BY handled_at DESC LIMIT 5;"
```

### Valkey操作
```bash
# Valkeyコンソール接続
docker-compose exec valkey valkey-cli -a valkey_password

# セッション確認
docker-compose exec valkey valkey-cli -a valkey_password KEYS "*session*"

# キャッシュ確認
docker-compose exec valkey valkey-cli -a valkey_password KEYS "*cache*"

# 全データクリア（開発時のみ）
docker-compose exec valkey valkey-cli -a valkey_password FLUSHALL
```

---

## 🧪 テスト

### OAuth2フローテスト（外部RPから）
1. 外部RPアプリケーション用クライアントを登録
2. 外部RPから認証URLアクセス:
```
https://idp.localhost/oauth2/auth?client_id=CLIENT_ID&response_type=code&scope=openid%20profile%20email&redirect_uri=https://your-rp-domain.com/auth/callback&state=test
```
3. IdP認証画面でログイン → 同意画面 → 外部RPへリダイレクト

### 信頼済みクライアントテスト（metadata方式）
```bash
# first-partyクライアント登録
./scripts/register-client.sh "https://your-rp-domain.com/auth/callback" --first-party

# 登録されたclient_idを使用してテスト
https://idp.localhost/oauth2/auth?client_id={GENERATED_CLIENT_ID}&response_type=code&scope=openid%20profile%20email&redirect_uri=https://your-rp-domain.com/auth/callback&state=test
```
→ 同意画面をスキップして自動同意（metadata判定）

### Cross-Domain SSO動作確認
```bash
# IdP側でログイン状態を確認
curl -k -H "Cookie: your_session_cookie" https://idp.localhost/profile

# 外部RP側でSSO実行（3回連続で実行し、動作ログを確認）
# IdPログを確認: docker-compose logs -f web | grep "IdP ENTRY"
```

---

## 📚 技術スタック

- **Container**: Docker + Docker Compose
- **Ruby**: 3.4.5
- **Rails**: 8.0.2.1
- **Database**: MySQL 8.0 (Rails + Hydra共用、内部接続のみ)
- **Cache/Session**: Valkey 8.0 (Rails専用、内部接続のみ)
- **OAuth2 Server**: ORY Hydra v2.3.0
- **Web Server**: nginx (HTTPS終端 + リバースプロキシ)

---

## 📖 設定ファイル

- **[docker/nginx/](./docker/nginx/)** - nginx SSL設定ファイル
- **[docker/hydra/](./docker/hydra/)** - ORY Hydra設定ファイル
- **[docker/mysql/](./docker/mysql/)** - MySQL初期化スクリプト
- **[scripts/](./scripts/)** - OAuth2クライアント登録スクリプト

---

## 🔧 トラブルシューティング

### よくある問題

#### Hydra JWKs エラー
```bash
# 開発環境でのJWKsリセット（DB初期化）
docker-compose exec db mysql -u rails hydra_development -prails_password -e "DROP DATABASE hydra_development; CREATE DATABASE hydra_development;"
docker-compose restart hydra
```

#### Cross-Origin Cookie問題
- `hydra.yml`の`cookies.same_site_mode: "None"`設定確認
- クライアント登録時のCORS設定確認
- ブラウザ開発者ツールでCookieのSameSite属性確認

#### セッション・キャッシュ問題
```bash
# Valkeyデータクリア
docker-compose exec valkey valkey-cli -a valkey_password FLUSHALL
```

---

**最終更新**: 2025-10-18