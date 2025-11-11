# Rails 8.0 SSO Identity Provider (IdP) - HTTPS対応版

**ORY Hydra v2.3.0**を活用したSSO認証システムのIdentity Provider

## 🚀 クイックスタート

### 初回セットアップ
```bash
# 1. リポジトリのクローン
git clone [repository]
cd sso-idp

# 2. 起動（初回は自動ビルド＋DB初期化＋スキーマ適用）
docker-compose up -d
```

起動時に以下が自動実行されます：
- Dockerイメージのビルド
- データベース作成（`rails db:prepare`）
- スキーマ適用（`rake ridgepole:apply`）
- Railsサーバー起動

### 動作確認
- **IdP認証画面**: https://localhost:4443

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
           │   (host port 4443)  │
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
HOST_NAME=localhost
HOST_PORT=4443
HYDRA_PUBLIC_URL=https://localhost:4443

# ログアウト戦略
LOGOUT_STRATEGY=local  # or 'global'
```

**注意**: 本番環境では、データベースパスワード、JWT秘密鍵、SSL証明書などを適切に変更してください。

## 🔑 RP登録

### RP登録の仕組み

RPを登録するには、以下の2つの登録が必要です：

1. **Hydra OAuth2クライアント登録**: OAuth2/OpenID Connect認証用
2. **IdP RelyingPartyマスタ登録**: IdP内部のRP管理用

**重要**: Hydra登録で発行される `CLIENT_ID` と `CLIENT_SECRET` を、IdP RPマスタでも**APIキーとして流用**します。これにより2重管理を避けています。

### 一括登録スクリプト（推奨）

開発環境では、上記2つを一括で登録するスクリプトを使用できます：

```bash
./scripts/register-rp-dev.sh "RP名" "callback_url" [OPTIONS]
```

**OPTIONS**:
- `--first-party`: 信頼済みクライアント（同意画面スキップ）
- `--cors-origin "domains"`: CORS許可オリジン（カンマ区切り）
- `--signin-url "URL"`: RPのログインページURL
- `--webhook-url "URL"`: ユーザー情報変更通知先URL

**登録例（ローカル開発環境）**:
```bash
./scripts/register-rp-dev.sh "検証用RP" "https://localhost:3443/auth/sso/callback" \
  --first-party \
  --cors-origin "https://localhost:4443,https://localhost:3443" \
  --signin-url "https://localhost:3443/auth/sso"
```

このスクリプトは以下を自動で行います：
1. Hydra OAuth2クライアントを登録
2. 発行された `CLIENT_ID` / `CLIENT_SECRET` を取得
3. それらを使用してIdP RelyingPartyマスタに登録

### 個別登録（手動で2段階登録する場合）

必要に応じて、Hydra登録とIdP RP登録を個別に実行することもできます：

#### Step 1: Hydra OAuth2クライアント登録
```bash
./scripts/register-hydra-client.sh "https://localhost:3443/auth/sso/callback" \
  --first-party \
  --cors-origin "https://localhost:4443,https://localhost:3443"
```

→ `CLIENT_ID` と `CLIENT_SECRET` をメモ

#### Step 2: IdP RelyingPartyマスタ登録
```bash
./scripts/register-idp-rp.sh "検証用RP" "localhost:3443" "<CLIENT_ID>" "<CLIENT_SECRET>" \
  --signin-url "https://localhost:3443/auth/sso"
```

### 登録結果の確認
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
docker-compose exec app bash
```

### Rails操作
```bash
# コンソール
docker-compose exec app bundle exec rails console

# マイグレーション
docker-compose exec app bundle exec rails db:migrate

# データベースリセット
docker-compose exec app bundle exec rails db:reset

# テスト実行
docker-compose exec app bundle exec rspec

# その他のRailsコマンド
docker-compose exec app bundle exec rails [command]
```

**注意**: Railsはappコンテナにクリーンインストールされており、ホスト上では動作しません。appコンテナ上では必ず`bundle exec`を付けて実行してください。

### DB操作

#### スキーマ管理（Ridgepole）

このプロジェクトはRidgepoleでスキーマ管理しています。

```bash
# スキーマ適用（自動：docker-compose up 時に実行）
# 手動で実行する場合：
docker-compose exec app rake ridgepole:apply

# 現在のスキーマをエクスポート（確認用）
docker-compose exec app bundle exec ridgepole -c config/database.yml -E development --export
```

**スキーマファイル**: `db/schemas/Schemafile`（各テーブルは`db/schemas/*.schema`）

#### MySQL接続
```bash
# MySQLコンソール接続
docker-compose exec db mysql -u rails idp_development -prails_password
```

### Hydra操作
```bash
# クライアント一覧
docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445

# ヘルスチェック
curl -k https://localhost:4443/health/ready

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
https://localhost:4443/oauth2/auth?client_id=CLIENT_ID&response_type=code&scope=openid%20profile%20email&redirect_uri=https://your-rp-domain.com/auth/callback&state=test
```
3. IdP認証画面でログイン → 同意画面 → 外部RPへリダイレクト

### 信頼済みクライアントテスト（metadata方式）
```bash
# first-partyクライアント登録
./scripts/register-client.sh "https://your-rp-domain.com/auth/callback" --first-party

# 登録されたclient_idを使用してテスト
https://localhost:4443/oauth2/auth?client_id={GENERATED_CLIENT_ID}&response_type=code&scope=openid%20profile%20email&redirect_uri=https://your-rp-domain.com/auth/callback&state=test
```
→ 同意画面をスキップして自動同意（metadata判定）

### Cross-Domain SSO動作確認
```bash
# IdP側でログイン状態を確認
curl -k -H "Cookie: your_session_cookie" https://localhost:4443/profile

# 外部RP側でSSO実行（3回連続で実行し、動作ログを確認）
# IdPログを確認: docker-compose logs -f app | grep "IdP ENTRY"
```

---

## 📚 技術スタック

- **Container**: Docker + Docker Compose
- **Ruby**: 3.4.7
- **Rails**: 8.0.3
- **Database**: MySQL 8.0 (Rails + Hydra共用、内部接続のみ)
- **Cache/Session**: Valkey 8.0 (Rails専用、内部接続のみ)
- **OAuth2 Server**: ORY Hydra v2.3.0
- **Web Server**: https-portal (nginxベース、証明書自動管理 + HTTPS終端 + リバースプロキシ)

---

## 📖 設定ファイル

- **[docker/https-portal/](./docker/https-portal/)** - https-portal設定ファイル（nginxベース）
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