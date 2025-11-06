# SSO認証システム - セットアップガイド

このSSO認証システムは2つの独立したリポジトリで構成されています：

1. **sso-idp**: https-portal (nginx) + Rails + ORY Hydraで実装したIdentity Provider (IdP)
2. **sso-rp**: Nginx + Railsで実装したRelying Party (RP) - IdP動作確認用アプリケーション

各リポジトリは完全に独立しており、別々にクローン・起動する必要があります。

## 📋 前提条件

- Docker & Docker Compose
- macOS/Linux/Windows環境

---

## 🚀 クイックスタート（初回セットアップ）

### ステップ1: IdPの起動

```bash
cd sso-idp
docker-compose up -d
```

初回起動時は自動的にビルドとDB初期化が実行されます。

**動作確認**:
- IdPトップページ: https://localhost:4443
- Hydraヘルスチェック: `curl -k https://localhost:4443/health/ready`

### ステップ2: テストユーザーの登録

IdPでSSO認証を行うためのテストユーザーを登録します。

1. **ユーザー仮登録**: https://localhost:4443 にアクセスし、サインアップフォームから登録
2. **確認メールの確認**: https://localhost:4443/letter_opener で仮登録メールを確認
3. **本登録**: メール内のリンクをクリックして本登録完了

> **補足**: IdPには`letter_opener` gemが組み込まれており、開発環境でのメール確認が可能です。

### ステップ3: RPの登録（IdP側で実行）

RPを使用するには、以下の2つの登録が必要です：
1. **Hydra OAuth2クライアント登録**: OAuth2/OpenID Connect認証用
2. **IdP RelyingPartyマスタ登録**: IdP内部のRP管理用

Hydra登録で発行される `CLIENT_ID` と `CLIENT_SECRET` を、IdP RPマスタでも**APIキーとして流用**します。

#### 一括登録スクリプト（推奨）

```bash
cd sso-idp
./scripts/register-rp-dev.sh "検証用RP" "https://localhost:3443/auth/sso/callback" \
  --first-party \
  --cors-origin "https://localhost:4443,https://localhost:3443" \
  --signin-url "https://localhost:3443/auth/sso"
```

このスクリプトは以下を自動で行います：
1. Hydra OAuth2クライアントを登録
2. 発行された `CLIENT_ID` / `CLIENT_SECRET` を取得
3. それらを使用してIdP RelyingPartyマスタに登録

実行後、以下の情報が表示されます（後で使用するのでメモしてください）：
- `CLIENT_ID`: クライアントID
- `CLIENT_SECRET`: クライアントシークレット

**オプション説明**:
- `--first-party`: 信頼済みクライアント（同意画面をスキップ）
- `--cors-origin "domains"`: CORS許可オリジン（カンマ区切り）
- `--signin-url "URL"`: RPのログインページURL
- `--webhook-url "URL"`: ユーザー情報変更通知先URL（オプション）

### ステップ4: RP側の環境設定

取得したクライアント認証情報をRP側に設定します。

```bash
cd sso-rp

# .env.localファイルを作成
cp .env.local.example .env.local

# エディタで.env.localを編集
# OAUTH_CLIENT_ID=<ステップ3で取得したCLIENT_ID>
# OAUTH_CLIENT_SECRET=<ステップ3で取得したCLIENT_SECRET>
```

`.env.local`の設定例：
```bash
OAUTH_CLIENT_ID=abc123def456...
OAUTH_CLIENT_SECRET=xyz789uvw012...
```

### ステップ5: RPの起動

```bash
cd sso-rp
docker-compose up -d
```

**動作確認**:
- RPトップページ: https://localhost:3443

---

## 🧪 動作テスト

### SSOログインフロー

1. **RPにアクセス**: https://localhost:3443
2. **SSOログイン開始**: "Login with SSO"ボタンをクリック
3. **IdPで認証**: `https://localhost:4443`の認証画面にリダイレクトされる
   - ステップ2で登録したメールアドレスとパスワードでログイン
   - 2段階認証コードを入力
4. **RPにリダイレクト**: 認証成功後、RPに戻りログイン状態になる
5. **ユーザー情報表示**: IdPから取得したユーザー情報が表示される

### ログアウト

- RPの"Logout"ボタンをクリック
- IdPのセッションもクリアされます（グローバルログアウト対応）

---

## 🏗️ システム構成

### アーキテクチャ概要

```
┌─────────────────────┐
│   Browser           │
└──────┬──────────────┘
       │ HTTPS
       │
       ├─────────────────────────────┐
       │                             │
       ▼                             ▼
┌─────────────────────┐    ┌─────────────────────┐
│  IdP (sso-idp)      │    │  RP (sso-rp)        │
│  localhost:4443     │◄───┤  localhost:3443     │
│                     │    │                     │
│  ┌───────────┐      │    │  ┌───────────┐      │
│  │  Rails    │      │    │  │  Rails    │      │
│  │   IdP     │◄────┐│    │  │   App     │      │
│  └───────────┘     ││    │  └───────────┘      │
│  ┌───────────┐     ││    └─────────────────────┘
│  │   Hydra   │◄────┘│
│  │  OAuth2   │      │
│  └───────────┘      │
│  ┌───────────┐      │
│  │   MySQL   │      │
│  └───────────┘      │
│  ┌───────────┐      │
│  │  Valkey   │      │
│  └───────────┘      │
└─────────────────────┘
```

### 認証フロー詳細

1. ユーザーがRPの「Login with SSO」をクリック
2. IdPの認証画面にリダイレクト（`https://localhost:4443/oauth2/auth?...`）
3. IdPでユーザー認証（メール・パスワード・2段階認証コード）
4. 信頼済みクライアントの場合、同意画面はスキップ
5. 認証コードを持ってRPにリダイレクト
6. RPがトークン交換・ユーザー情報取得
7. RPでセッション確立・ログイン完了

---

## 📝 よく使うコマンド

### IdP操作

```bash
cd sso-idp

# サービスの起動・停止
docker-compose up -d
docker-compose down

# ログ確認
docker-compose logs -f

# 登録済みOAuth2クライアント一覧
docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445

# Railsコンソール
docker-compose exec app bundle exec rails console

# データベース接続
docker-compose exec db mysql -u rails idp_development -prails_password

# Valkeyセッション確認
docker-compose exec valkey valkey-cli -a valkey_password KEYS "*session*"
```

### RP操作

```bash
cd sso-rp

# サービスの起動・停止
docker-compose up -d
docker-compose down

# ログ確認
docker-compose logs -f

# Railsコンソール
docker-compose exec app bundle exec rails console
```

---

## 🔧 トラブルシューティング

### よくある問題

#### 1. IdPに接続できない

```bash
# IdPの起動確認
curl -k https://localhost:4443/health/ready

# DockerコンテナがポートをLISTENしているか確認
docker-compose ps
# nginxコンテナが 0.0.0.0:4443->443/tcp でマッピングされているか確認
```

#### 2. OAuth2認証エラー

- IdPでクライアントが正しく登録されているか確認:
  ```bash
  cd sso-idp
  docker-compose exec hydra hydra list oauth2-clients --endpoint http://localhost:4445
  ```
- RP側の`.env.local`に正しいCLIENT_IDとCLIENT_SECRETが設定されているか確認
- リダイレクトURIが`https://localhost:3443/auth/sso/callback`で登録されているか確認

#### 3. ユーザー登録メールが届かない

開発環境では実際のメールは送信されません。以下のURLでメールを確認してください：
- https://localhost:4443/letter_opener

#### 4. SSL証明書エラー

開発環境では自己署名証明書を使用しているため、ブラウザで警告が表示されます。
「詳細設定」→「安全でないサイトに進む」で進んでください。

#### 5. セッション・キャッシュ問題

```bash
cd sso-idp

# Valkeyデータクリア
docker-compose exec valkey valkey-cli -a valkey_password FLUSHALL

# Hydra JWKsリセット（必要に応じて）
docker-compose exec db mysql -u rails hydra_development -prails_password -e \
  "DROP DATABASE hydra_development; CREATE DATABASE hydra_development;"
docker-compose restart hydra
```

---

## 📚 技術スタック

### IdP (sso-idp)

- **Container**: Docker + Docker Compose
- **Ruby**: 3.4.7
- **Rails**: 8.0.3
- **Database**: MySQL 8.0
- **Cache/Session**: Valkey 8.0
- **OAuth2 Server**: ORY Hydra v2.3.0
- **Web Server**: https-portal (nginxベース、証明書自動管理 + HTTPS)

### RP (sso-rp)

- **Container**: Docker + Docker Compose
- **Ruby**: 3.2.6
- **Rails**: 7.1.5
- **Authentication**: OmniAuth + OpenID Connect
- **Web Server**: nginx (HTTPS)

---

## 📖 詳細ドキュメント

各プロジェクトの詳細な設定やAPI仕様については、それぞれのREADMEを参照してください：

- **IdP詳細**: [sso-idp/README.md](https://github.com/nagashima/sso-idp/blob/main/README.md)
- **RP詳細**: [sso-rp/README.md](https://github.com/nagashima/sso-rp/blob/main/README.md)

---

## 🔑 主要な設定ファイル

### IdP

- `sso-idp/.env` - 環境変数設定
- `sso-idp/docker-compose.yml` - Docker構成
- `sso-idp/docker/https-portal/` - https-portal設定（nginxベース）
- `sso-idp/docker/hydra/` - ORY Hydra設定
- `sso-idp/scripts/register-client.sh` - OAuth2クライアント登録スクリプト

### RP

- `sso-rp/.env` - デフォルト環境変数
- `sso-rp/.env.local` - ローカル環境変数（gitignore、個別設定）
- `sso-rp/docker-compose.yml` - Docker構成
- `sso-rp/docker/nginx/` - nginx SSL設定
- `sso-rp/config/initializers/omniauth.rb` - OmniAuth設定

---

## 🚦 セットアップチェックリスト

初回セットアップ時は以下の順序で実行してください：

- [ ] IdPを起動（`cd sso-idp && docker-compose up -d`）
- [ ] IdPでテストユーザーを登録（https://localhost:4443）
- [ ] letter_openerでメール確認・本登録完了（https://localhost:4443/letter_opener）
- [ ] IdPでRPを登録（`./scripts/register-rp-dev.sh "検証用RP" "https://localhost:3443/auth/sso/callback" --first-party ...`）
- [ ] CLIENT_IDとCLIENT_SECRETをメモ
- [ ] RP側で`.env.local`を作成・編集
- [ ] RPを起動（`cd sso-rp && docker-compose up -d`）
- [ ] RPでSSOログインをテスト（https://localhost:3443）

---

**最終更新**: 2025-10-20
