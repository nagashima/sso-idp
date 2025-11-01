# SSOフロー中の会員登録機能 最終仕様書

**Version**: 1.3.0
**作成日**: 2025-10-31
**最終更新**: 2025-11-01
**Status**: 最終版（実装準備完了）

**変更履歴**:
- v1.3.0: Rails設計思想を追加（Service層設計原則、API URL設計思想、Controller設計パターン、Service層詳細設計、テストピラミッド）
- v1.2.0: バリデーション戦略追加（Form Objects + React Hook Form + Zod）
- v1.1.0: ridgepole採用、Phase 1分割、React Router + エントリポイント2つ、CredentialsStep命名

---

## 📋 目次

1. [概要・背景](#概要背景)
2. [全体アーキテクチャ](#全体アーキテクチャ)
3. [Rails設計思想](#rails設計思想)
4. [URL設計](#url設計)
5. [会員登録フロー詳細](#会員登録フロー詳細)
6. [DB設計](#db設計)
7. [キャッシュ設計](#キャッシュ設計)
8. [Service層の詳細設計](#service層の詳細設計)
9. [Controller設計](#controller設計)
10. [React実装設計](#react実装設計)
11. [バリデーション戦略](#バリデーション戦略)
12. [段階的実装計画](#段階的実装計画)
13. [設定変更](#設定変更)
14. [セキュリティ・認証設計](#セキュリティ認証設計)
15. [データモデルの特殊制約](#データモデルの特殊制約)
16. [将来の拡張機能](#将来の拡張機能)
17. [テスト戦略](#テスト戦略)

---

## 概要・背景

### 目的

IdPで以下2つの機能を実現する：

1. **新しい会員登録フロー**：メール確認を先行する方式に変更
   - 現在：属性入力 → メール送信 → 確認
   - 新仕様：メール入力 → メール確認 → パスワード設定 → 属性入力 → 確認 → 登録完了

2. **SSOフロー中の会員登録**：RP経由でIdPに来た未登録ユーザーがその場で会員登録
   - ログイン画面に「新規登録」リンク
   - 登録完了後、自動的にSSOフローに復帰してRPにログイン

### 参考実装

- **RP実装**（`/Users/n/Workspace/2049/postnatal-care`）：
  - 会員登録フロー（メール確認先行型）
  - Services/Forms層のアーキテクチャ
  - Redisキャッシュパターン
  - React + ViteのマイクロSPAパターン

- **既存試作版**（`/Users/n/Workspace/Labo/work/idp/app/frontend`）：
  - Vite + React + TypeScript環境構築済み
  - ログイン・会員登録のエントリポイント
  - TailwindCSS統合

---

## 全体アーキテクチャ

### システム構成

```
┌─────────────────────────────────────────────────────────────┐
│                         IdP System                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐      ┌─────────────────┐             │
│  │  通常WEB機能    │      │   SSO機能       │             │
│  │  /users/*       │      │   /sso/*        │             │
│  ├─────────────────┤      ├─────────────────┤             │
│  │ - sign_in       │      │ - sign_in       │             │
│  │ - sign_up       │      │ - sign_up       │             │
│  │ - sign_out      │      │ - sign_out      │             │
│  │                 │      │ - consent       │             │
│  └─────────────────┘      └─────────────────┘             │
│           │                        │                        │
│           └────────────┬───────────┘                        │
│                        ↓                                    │
│         ┌──────────────────────────┐                       │
│         │   Rails Controllers      │                       │
│         │   - Users::*Controller   │                       │
│         │   - Sso::*Controller     │                       │
│         └──────────────────────────┘                       │
│                        │                                    │
│         ┌──────────────┼──────────────┐                    │
│         ↓              ↓              ↓                    │
│    ┌────────┐    ┌─────────┐    ┌────────┐               │
│    │Services│    │  Models │    │ Forms  │               │
│    └────────┘    └─────────┘    └────────┘               │
│         │              │              │                    │
│         └──────────────┼──────────────┘                    │
│                        ↓                                    │
│         ┌──────────────────────────┐                       │
│         │  PostgreSQL + Valkey     │                       │
│         └──────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
                         │
                         ↓
           ┌─────────────────────────┐
           │   Ory Hydra (OAuth2)    │
           │   - /oauth2/*           │
           │   - Admin API (4445)    │
           └─────────────────────────┘
                         │
                         ↓
           ┌─────────────────────────┐
           │   RP Application        │
           └─────────────────────────┘
```

---

## Rails設計思想

### Service層の設計原則

#### 設計思想

**基本原則**：
- **Controller層は薄く**: パラメータ受け取り → Service委譲 → レスポンス返却のみ
- **Service層は厚く**: 業務ロジック、バリデーション、トランザクション、外部連携
- **テスト戦略**: Serviceで機能テストを完全カバー、Controllerテストは最小限

```
┌─────────────────────────────────────┐
│ Controller層（薄い）                │
│ - パラメータ受け取り                │
│ - Serviceへ委譲                     │
│ - レスポンス返却                    │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ Service層（厚い）                   │
│ - 業務ロジック                      │
│ - バリデーション                    │
│ - トランザクション                  │
│ - 外部連携                          │
│ ↓ Serviceテスト：機能テスト         │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ Model層                             │
└─────────────────────────────────────┘
```

#### Service分類

**モデル単位のService（基本パターン）**：
- `SignupTicketService`: SignupTicketモデルの操作
- `UserService`: Userモデルの作成・更新

**機能単位のService（特殊パターン）**：
- `CacheService`: Valkeyキャッシュ操作
- `HydraClientService`: Hydra Admin API連携
- `AuthenticationLoggerService`: 認証ログ記録
- `SignupService`: 登録フロー統括（複数モデル横断）

**参考**: 既存RP（`/Users/n/Workspace/2049/postnatal-care`）の設計パターン
- `UserReservationSlotService`: モデル単位
- `DigitalAuthService`: 外部API連携

---

### API URL設計思想

#### 基本原則: 機能ごとの縦割り

機能単位で URL を縦割りに構成し、内部APIと外部APIを明確に分離：

```
機能 = エントリポイント + 内部API

/users/     → Users機能（通常ログイン・登録）
  ├── sign_in                  # ページ
  ├── sign_up                  # ページ
  └── api/                     # 内部API（React用）
      ├── sign_in/*
      └── sign_up/*

/sso/       → SSO機能（OIDC連携）
  ├── sign_in                  # ページ
  ├── sign_up                  # ページ
  └── api/                     # 内部API（React用）
      └── sign_up/*

/api/v1/    → API機能（RP向け外部提供）
  ├── rp_clients
  └── users
```

#### 例外: API機能（外部提供専用）

`/api/v1/` → RP向けサーバ間通信（バージョニングあり）

#### 認証方式の違い

| API種類 | 認証方式 | 用途 |
|---------|---------|------|
| `/users/api/*`, `/sso/api/*` | Cookie (JWT) | React ↔ Rails |
| `/api/v1/*` | Bearer Token / API Key | RP Server ↔ IdP Server |

#### 設計の利点

1. **開発者の迷いがない**: 機能単位で配置が明確
2. **責務が明確**: 各機能が独立して管理できる
3. **将来の拡張が容易**: 新機能追加時に他への影響が最小限
4. **認証方式の切り分けが自然**: 内部/外部でコントローラー基底クラスを分離

---

## URL設計

### 設計思想

**基本**: 機能ごとの縦割り
**例外**: API機能（外部提供）

### Users機能（通常WEB）

```
GET  /users/sign_in                              # ログイン画面
GET  /users/sign_up                              # 会員登録画面

POST /users/api/sign_in/authenticate             # 認証API
POST /users/api/sign_in/verify                   # 2FA検証API

POST /users/api/sign_up/email_verification       # メール送信API
POST /users/api/sign_up/password                 # パスワード保存API
POST /users/api/sign_up/profile                  # プロフィール保存API
POST /users/api/sign_up/registration             # 登録完了API

DELETE /users/sign_out                           # ログアウト
```

### SSO機能（OIDC連携）

```
GET  /sso/sign_in?login_challenge=xxx            # SSOログイン画面
GET  /sso/sign_up?login_challenge=xxx            # SSO会員登録画面

POST /sso/api/sign_in/authenticate               # 認証API
POST /sso/api/sign_in/verify                     # 2FA検証API

POST /sso/api/sign_up/email_verification         # メール送信API
POST /sso/api/sign_up/password                   # パスワード保存API
POST /sso/api/sign_up/profile                    # プロフィール保存API
POST /sso/api/sign_up/registration               # 登録完了API（Hydra連携）

GET  /sso/consent?consent_challenge=xxx          # 同意画面
POST /sso/consent                                # 同意処理
GET  /sso/sign_out?logout_challenge=xxx          # SSOログアウト
```

### RP向けAPI（外部提供）

```
GET    /api/v1/rp_clients                        # RpClient一覧
POST   /api/v1/rp_clients                        # RpClient登録
GET    /api/v1/rp_clients/:id                    # RpClient詳細
PATCH  /api/v1/rp_clients/:id                    # RpClient更新
DELETE /api/v1/rp_clients/:id                    # RpClient削除

GET    /api/v1/users/:id                         # User情報取得
GET    /api/v1/users/search?email=xxx            # User検索
```

### OIDC API（Hydra）

```
GET  /oauth2/auth                                # 認可エンドポイント
POST /oauth2/token                               # トークンエンドポイント
GET  /oauth2/userinfo                            # ユーザー情報エンドポイント
```

### 認証方式の違い

| API種類 | 認証方式 | 用途 |
|---------|---------|------|
| `/users/api/*`, `/sso/api/*` | Cookie (JWT) | React ↔ Rails |
| `/api/v1/*` | Bearer Token / API Key | RP Server ↔ IdP Server |
| `/oauth2/*` | OAuth2 Authorization Code | 標準OIDCフロー |

### nginx リバースプロキシ設定

```nginx
# IdP SSO機能（Hydra連携のUI）
location /sso/ {
    proxy_pass http://app:3000;
}

# Hydra Public API（OAuth2プロトコル）
location /oauth2/ {
    proxy_pass http://hydra:4444;
}

# Hydra関連エンドポイント
location /health/ {
    proxy_pass http://hydra:4444;
}

location /.well-known/ {
    proxy_pass http://hydra:4444;
}

location /userinfo {
    proxy_pass http://hydra:4444/userinfo;
}

# IdP通常WEB機能
location / {
    proxy_pass http://app:3000;
}
```

---

## 会員登録フロー詳細

### 通常登録フロー

```
【ユーザー】IdPに直接訪問
  ↓
1. GET /users/sign_up
   - React SPAマウント
   - Step 1: メールアドレス入力画面表示
   ↓
2. POST /users/api/sign_up/email
   - SignupTicket作成（token発行）
   - 確認メール送信
   - Step 2: 「メールを確認してください」画面表示
   ↓
3. 【ユーザー】メールのリンクをクリック
   GET /users/verify_email/:token
   - トークン検証
   - confirmed_at設定
   - Step 3へリダイレクト: /users/sign_up/password?token=xxx
   ↓
4. Step 3: パスワード入力
   POST /users/api/sign_up/password
   - パスワードをValkeyに保存: signup:#{token}:password
   - Step 4へ遷移
   ↓
5. Step 4: 属性入力（名前、生年月日等）
   POST /users/api/sign_up/profile
   - 属性をValkeyに保存: signup:#{token}:profile
   - Step 5へ遷移
   ↓
6. Step 5: 確認画面
   - Valkeyから全データ取得して表示
   ↓
7. Step 6: 「アカウントを作成する」ボタン
   POST /users/api/sign_up/complete
   - Valkeyから全データ取得
   - User作成（activated=true）
   - ログインセッション確立（JWT cookie）
   - Valkeyキャッシュ削除
   - SignupTicketレコード削除
   - トップページへリダイレクト
```

### SSOフロー中の登録

```
【RP】ログインボタンクリック
  ↓
GET https://idp.example.com/oauth2/auth?
  client_id=xxx
  &redirect_uri=https://rp.example.com/callback
  &state={"inviteCode":"abc123"}
  &scope=openid profile email
  &response_type=code
  ↓
【Hydra】未ログイン判定 → login_challenge発行
  ↓
302 https://idp.example.com/sso/sign_in?login_challenge=xyz123
  ↓
【IdP】SSOログイン画面表示
  ↓
【ユーザー】「新規登録」リンクをクリック
  ↓
GET /sso/sign_up?login_challenge=xyz123
  ↓
1. React SPAマウント（login_challengeをmeta tagで渡す）
   Step 1: メールアドレス入力画面
   ↓
2. POST /users/api/sign_up/email
   body: { email, login_challenge }
   - SignupTicket作成
   - Valkeyに保存: signup:#{token}:login_challenge = xyz123
   - 確認メール送信
   ↓
3-5. 通常登録フローと同じ
   ↓
6. POST /users/api/sign_up/complete
   - Valkeyから全データ取得（login_challenge含む）
   - User作成
   - ログインセッション確立
   - Valkeyキャッシュ削除
   - SignupTicketレコード削除

   ★ login_challengeがある場合 ★
   - HydraAdminClient.accept_login_request(login_challenge, user.id)
   - redirect_to: Hydraのリダイレクト先URL
   ↓
【Hydra】consent_challenge発行
  ↓
302 https://idp.example.com/sso/consent?consent_challenge=abc456
  ↓
【IdP】同意画面（first-partyなら自動承認）
  ↓
【Hydra】認可コード発行
  ↓
302 https://rp.example.com/callback?code=xxx&state={"inviteCode":"abc123"}
  ↓
【RP】トークン交換 → ログイン完了
```

---

## DB設計

### DB管理方針

**ridgepole採用**：既存RPと合わせてridgepoleでスキーマ管理

```bash
# スキーマ反映
bundle exec ridgepole --apply -E development --file db/Schemafile

# スキーマ確認
bundle exec ridgepole --export -E development
```

### SignupTicketテーブル（新規作成）

**Phase 1-A: 最小限版**

```ruby
# db/Schemafile
create_table "signup_tickets", force: :cascade do |t|
  t.string :email, null: false
  t.string :token, null: false
  t.datetime :expires_at, null: false
  t.datetime :confirmed_at
  t.timestamps

  t.index :token, unique: true
  t.index :email
  t.index :expires_at
end
```

**Phase 1-B: 完全版（将来の拡張）**

```ruby
# db/Schemafile（Phase 1-Bで拡張）
create_table "signup_tickets", force: :cascade do |t|
  t.string :email, null: false
  t.string :token, null: false
  t.datetime :expires_at, null: false
  t.datetime :confirmed_at

  # Phase 1-Bで追加検討
  t.string :ip_address           # 登録元IP
  t.integer :resend_count, default: 0  # 再送回数

  t.timestamps

  t.index :token, unique: true
  t.index :email
  t.index :expires_at
end
```

### SignupTicketモデル

```ruby
# app/models/signup_ticket.rb
class SignupTicket < ApplicationRecord
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # トークン生成
  def self.generate_token
    SecureRandom.urlsafe_base64(32)  # 64文字
  end

  # 有効期限チェック
  def expired?
    expires_at < Time.current
  end

  # メール確認済みか
  def confirmed?
    confirmed_at.present?
  end

  # 登録に使用可能か
  def valid_for_signup?
    confirmed? && !expired?
  end
end
```

### Userテーブル（既存拡張）

**Phase 1-A: 最小限版**

```ruby
# db/Schemafile（Phase 1-A：既存拡張）
create_table "users", force: :cascade do |t|
  # 基本情報
  t.string :email, null: false
  t.string :encrypted_password, null: false

  # アカウント状態
  t.boolean :activated, default: false, null: false
  t.datetime :activated_at

  # 2FA（既存維持）
  t.string :auth_code
  t.datetime :auth_code_expires_at

  t.timestamps

  t.index :email, unique: true
end
```

**Phase 1-B: 属性追加版**

```ruby
# db/Schemafile（Phase 1-B：属性追加）
create_table "users", force: :cascade do |t|
  # 基本情報
  t.string :email, null: false
  t.string :encrypted_password, null: false

  # プロフィール（Phase 1-Bで追加）
  t.string :name, null: false
  t.date :birth_date
  t.string :phone_number
  t.string :postal_code
  t.text :address

  # アカウント状態
  t.boolean :activated, default: false, null: false
  t.datetime :activated_at

  # 2FA
  t.string :auth_code
  t.datetime :auth_code_expires_at

  # 監査（Phase 1-Bで追加検討）
  t.datetime :last_sign_in_at
  t.string :last_sign_in_ip

  t.timestamps

  t.index :email, unique: true
end
```

**備考**：
- 既存の`activation_token`、`activation_expires_at`は削除せず残す（将来的な用途に備える）
- 新規登録フローでは`SignupTicket`を使用（Userの上記カラムは使用しない）

---

## キャッシュ設計

### Valkeyキャッシュパターン

```ruby
# app/services/cache_service.rb
class CacheService
  # 1. 未ログイン会員登録フロー用（tokenベース）
  def self.save_signup_cache(token, key, value, expires_in: 24.hours)
    Rails.cache.write("signup:#{token}:#{key}", value, expires_in: expires_in)
  end

  def self.get_signup_cache(token, key)
    Rails.cache.read("signup:#{token}:#{key}")
  end

  def self.delete_signup_cache(token)
    # パターンマッチで全削除
    Rails.cache.delete_matched("signup:#{token}:*")
  end

  # 2. ログイン済みユーザー用（user.idベース）
  def self.save_user_cache(user_id, key, value, expires_in: 30.minutes)
    Rails.cache.write("user:#{user_id}:#{key}", value, expires_in: expires_in)
  end

  def self.get_user_cache(user_id, key)
    Rails.cache.read("user:#{user_id}:#{key}")
  end

  def self.delete_user_cache(user_id, key)
    Rails.cache.delete("user:#{user_id}:#{key}")
  end
end
```

### キャッシュキーの使い分け

| 状況 | パターン | キーの形式 | 例 |
|------|---------|-----------|-----|
| **会員登録中（未ログイン）** | tokenベース | `signup:#{token}:#{key}` | `signup:abc123...:password` |
| **ログイン後のフォーム** | user.idベース | `user:#{user_id}:#{key}` | `user:123:draft` |

### 会員登録で保存するキャッシュ

| キー | 内容 | 有効期限 |
|------|------|---------|
| `signup:#{token}:password` | 暗号化済みパスワード | 24時間 |
| `signup:#{token}:profile` | 属性情報（JSON） | 24時間 |
| `signup:#{token}:login_challenge` | Hydra login_challenge（SSO用） | 24時間 |

---

## Service層の詳細設計

### SignupService（登録フロー統括）

複数モデルを横断する登録フローを管理。

#### Result Objectパターン

```ruby
# app/services/signup_service.rb
class SignupService
  class Result
    attr_reader :user, :error_message

    def initialize(success:, user: nil, error_message: nil)
      @success = success
      @user = user
      @error_message = error_message
    end

    def success?
      @success
    end
  end

  def self.complete_registration(token:, request:)
    # 1. トークン検証
    signup_ticket = SignupTicketService.find_valid_ticket(token)
    return Result.new(success: false, error_message: '無効なトークン') if signup_ticket.nil?

    # 2. キャッシュデータ取得
    cached_data = CacheService.get_signup_data(token)
    return Result.new(success: false, error_message: 'データが見つかりません') if cached_data.nil?

    # 3. User作成（トランザクション）
    user = UserService.create_from_signup(
      email: signup_ticket.email,
      encrypted_password: cached_data[:password],
      profile: cached_data[:profile]
    )

    return Result.new(success: false, error_message: user.errors.full_messages.join(', ')) if user.nil?

    # 4. クリーンアップ
    CacheService.delete_signup_cache(token)
    SignupTicketService.mark_as_used(signup_ticket)

    # 5. ログ記録
    AuthenticationLoggerService.log_user_registration(user, request)

    Result.new(success: true, user: user)
  rescue => e
    Rails.logger.error "SignupService.complete_registration failed: #{e.message}"
    Result.new(success: false, error_message: 'システムエラーが発生しました')
  end
end
```

**設計のポイント**：
- Result Objectで成功/失敗を明示的に表現
- 複数のServiceを組み合わせて高レベルの業務フローを実現
- エラーハンドリングを一箇所に集約

---

### SignupTicketService（モデル単位）

SignupTicketモデルの操作を担当。

**主要メソッド**：
- `create_ticket(email:)` - トークン生成・DB保存
- `find_valid_ticket(token)` - トークン検証（有効期限・確認済みチェック）
- `mark_as_confirmed(token)` - メール確認済みマーク
- `mark_as_used(signup_ticket)` - 使用済みマーク（削除）

```ruby
# app/services/signup_ticket_service.rb
class SignupTicketService
  def self.create_ticket(email:)
    SignupTicket.create!(
      email: email,
      token: SignupTicket.generate_token,
      expires_at: 24.hours.from_now
    )
  end

  def self.find_valid_ticket(token)
    ticket = SignupTicket.find_by(token: token)
    return nil unless ticket
    return nil if ticket.expired?
    return nil unless ticket.confirmed?
    ticket
  end

  def self.mark_as_confirmed(token)
    ticket = SignupTicket.find_by(token: token)
    return false unless ticket
    return false if ticket.expired?

    ticket.update!(confirmed_at: Time.current)
    true
  end

  def self.mark_as_used(signup_ticket)
    signup_ticket.destroy
  end
end
```

---

### UserService（モデル単位）

Userモデルの作成・更新を担当。

**主要メソッド**：
- `create_from_signup(email:, encrypted_password:, profile:)` - 登録からUser作成
- `update_profile(user, profile)` - プロフィール更新

```ruby
# app/services/user_service.rb
class UserService
  def self.create_from_signup(email:, encrypted_password:, profile:)
    User.create!(
      email: email,
      encrypted_password: encrypted_password,
      **profile.symbolize_keys,
      activated: true,
      activated_at: Time.current
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UserService.create_from_signup failed: #{e.message}"
    nil
  end

  def self.update_profile(user, profile)
    user.update!(profile.symbolize_keys)
  end
end
```

---

### CacheService（機能単位）

Valkeyキャッシュ操作を担当。

**主要メソッド**：
- `save_signup_cache(token, key, value)` - キャッシュ保存
- `get_signup_cache(token, key)` - キャッシュ取得
- `get_signup_data(token)` - 全データ取得（password + profile）
- `delete_signup_cache(token)` - キャッシュ削除

```ruby
# app/services/cache_service.rb
class CacheService
  def self.save_signup_cache(token, key, value, expires_in: 24.hours)
    Rails.cache.write("signup:#{token}:#{key}", value, expires_in: expires_in)
  end

  def self.get_signup_cache(token, key)
    Rails.cache.read("signup:#{token}:#{key}")
  end

  def self.get_signup_data(token)
    password = get_signup_cache(token, 'password')
    profile = get_signup_cache(token, 'profile')

    return nil if password.nil? || profile.nil?

    { password: password, profile: profile }
  end

  def self.delete_signup_cache(token)
    Rails.cache.delete_matched("signup:#{token}:*")
  end
end
```

---

### HydraClientService（機能単位）

Hydra Admin API連携を担当。

**主要メソッド**：
- `accept_login_request(challenge, user_id)` - ログイン承認
- `accept_consent_request(challenge, scopes)` - 同意承認

```ruby
# app/services/hydra_client_service.rb
class HydraClientService
  def self.accept_login_request(challenge, user_id, remember: true, remember_for: 3600)
    response = HydraAdminClient.accept_login_request(
      challenge,
      user_id.to_s,
      remember: remember,
      remember_for: remember_for
    )
    response['redirect_to']
  rescue => e
    Rails.logger.error "HydraClientService.accept_login_request failed: #{e.message}"
    raise HydraError, e.message
  end

  def self.accept_consent_request(challenge, user, scopes)
    response = HydraAdminClient.accept_consent_request(
      challenge,
      user.id.to_s,
      scopes: scopes,
      id_token: {
        sub: user.id.to_s,
        email: user.email,
        name: user.name
      }
    )
    response['redirect_to']
  end
end
```

---

### AuthenticationLoggerService（機能単位）

認証ログ記録を担当。

**主要メソッド**：
- `log_user_registration(user, request, **options)` - 会員登録ログ
- `log_login(user, request, **options)` - ログインログ

```ruby
# app/services/authentication_logger_service.rb
class AuthenticationLoggerService
  def self.log_user_registration(user, request, login_method: 'normal')
    Rails.logger.info({
      event: 'user_registration',
      user_id: user.id,
      email: user.email,
      login_method: login_method,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def self.log_login(user, request, login_method: 'normal')
    Rails.logger.info({
      event: 'user_login',
      user_id: user.id,
      email: user.email,
      login_method: login_method,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      timestamp: Time.current.iso8601
    }.to_json)
  end
end
```

---

## Controller設計

### ディレクトリ構造

```
app/controllers/
├── users/
│   ├── sign_in_controller.rb          # 通常ログイン（親クラス）
│   ├── sign_up_controller.rb          # 通常登録（親クラス）
│   └── api/
│       └── sign_up/
│           ├── email_verification_controller.rb
│           ├── password_controller.rb
│           ├── profile_controller.rb
│           └── registration_controller.rb
└── sso/
    ├── sign_in_controller.rb          # SSOログイン（子クラス、継承）
    ├── sign_up_controller.rb          # SSO登録（子クラス、継承）
    ├── sign_out_controller.rb         # SSOログアウト
    └── consent_controller.rb          # 同意画面
```

### 基底コントローラー設計

内部API（React用）と外部API（RP用）で基底クラスを分離し、認証方式を切り替え：

```ruby
# app/controllers/users/api/api_controller.rb
class Users::Api::ApiController < ApplicationController
  # Cookie認証、CSRF必須
  before_action :verify_authenticity_token
  before_action :authenticate_user_from_jwt_cookie!

  private

  def authenticate_user_from_jwt_cookie!
    token = cookies[:auth_token]
    return render_unauthorized unless token

    begin
      payload = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find(payload['user_id'])
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized
    end
  end

  def render_unauthorized
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end

# app/controllers/api/v1/v1_controller.rb
class Api::V1::V1Controller < ApplicationController
  # Bearer Token認証
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_token!

  private

  def authenticate_api_token!
    token = request.headers['Authorization']&.remove('Bearer ')
    return render_unauthorized unless token

    # API Key検証ロジック
    @current_rp_client = RpClient.find_by(api_key: token)
    render_unauthorized unless @current_rp_client
  end

  def render_unauthorized
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end
```

### Template Methodパターン

#### 親クラス：Users::SignUpController

```ruby
# app/controllers/users/sign_up_controller.rb
class Users::SignUpController < ApplicationController
  # Reactエントリポイント
  def index
    render layout: 'react_page'
  end

  protected

  # テンプレートメソッド：メール送信後の処理
  # 通常フローでは何もしない
  def handle_email_sent(confirmation, params)
    # 子クラスでオーバーライド可能
  end

  # テンプレートメソッド：登録成功後の処理
  # 通常フローではトップページへ
  def handle_signup_success(user, token)
    AuthenticationLoggerService.log_user_registration(user, request)
    render json: { success: true, redirect_to: root_path }
  end
end
```

#### 子クラス：Sso::SignUpController

```ruby
# app/controllers/sso/sign_up_controller.rb
class Sso::SignUpController < Users::SignUpController
  # SSOエントリポイント（login_challengeを受け取る）
  def index
    @login_challenge = params[:login_challenge]
    super
  end

  protected

  # オーバーライド：メール送信時にlogin_challengeをキャッシュ
  def handle_email_sent(signup_ticket, params)
    if params[:login_challenge].present?
      CacheService.save_signup_cache(
        signup_ticket.token,
        'login_challenge',
        params[:login_challenge]
      )
    end
  end

  # オーバーライド：登録成功時にHydraフローへ
  def handle_signup_success(user, token)
    login_challenge = CacheService.get_signup_cache(token, 'login_challenge')

    if login_challenge.present?
      AuthenticationLoggerService.log_user_registration(
        user,
        request,
        login_method: 'sso_signup'
      )

      begin
        redirect_uri = accept_hydra_login_request(login_challenge, user)
        render json: { success: true, redirect_to: redirect_uri }
      rescue HydraError => e
        Rails.logger.warn "Hydra challenge expired: #{e.message}"
        render json: {
          success: true,
          redirect_to: root_path,
          notice: '登録完了しました。RP側から再度ログインしてください。'
        }
      end
    else
      super
    end
  end

  private

  def accept_hydra_login_request(challenge, user)
    response = HydraAdminClient.accept_login_request(
      challenge,
      user.id.to_s,
      remember: true,
      remember_for: 3600
    )
    response['redirect_to']
  end
end
```

### API Controller設計パターン

Controller は業務ロジックを持たず、Service に委譲する設計を徹底：

#### ❌ Before: 業務ロジックがControllerに

```ruby
# app/controllers/users/api/sign_up/registration_controller.rb
class Users::Api::SignUp::RegistrationController < Users::Api::ApiController
  def complete
    signup_ticket = SignupTicket.find_by(token: params[:token])
    return render_error('無効なトークン') if signup_ticket.nil?
    return render_error('期限切れ') if signup_ticket.expired?
    return render_error('メール未確認') unless signup_ticket.confirmed?

    # Valkeyから全データ取得
    password = CacheService.get_signup_cache(params[:token], 'password')
    profile = CacheService.get_signup_cache(params[:token], 'profile')

    return render_error('データが見つかりません') if password.nil? || profile.nil?

    # User作成（20行以上の業務ロジック）
    user = User.create!(
      email: signup_ticket.email,
      encrypted_password: password,
      **profile.symbolize_keys,
      activated: true,
      activated_at: Time.current
    )

    # ログインセッション確立
    set_jwt_cookie(user)

    # 後処理
    CacheService.delete_signup_cache(params[:token])
    signup_ticket.destroy

    # フロー固有処理（Template Method）
    handle_signup_success(user, params[:token])
  end

  private

  def render_error(message)
    render json: { success: false, error: message }, status: :unprocessable_entity
  end
end
```

**問題点**：
- 業務ロジックがControllerに直接記述されている
- テストが遅い（HTTP層を通す必要がある）
- ロジックの再利用が困難

#### ✅ After: Service委譲のみ

```ruby
# app/controllers/users/api/sign_up/registration_controller.rb
class Users::Api::SignUp::RegistrationController < Users::Api::ApiController
  def complete
    result = SignupService.complete_registration(
      token: params[:token],
      request: request
    )

    if result.success?
      set_jwt_cookie(result.user)
      handle_signup_success(result.user, params[:token])
    else
      render_error(result.error_message)
    end
  end

  private

  def render_error(message)
    render json: { success: false, error: message }, status: :unprocessable_entity
  end
end
```

**改善点**：
- Controllerは薄く（パラメータ受け取り → Service委譲 → レスポンス返却）
- 業務ロジックはSignupServiceに集約
- テストが高速（Service単体テストで完全カバー）
- ロジックの再利用が容易（他のControllerからも呼び出し可能）

---

## React実装設計

### 技術スタック

| 項目 | 技術 |
|------|------|
| **ビルドツール** | Vite + vite-plugin-ruby |
| **フレームワーク** | React 19.2.0 |
| **言語** | TypeScript (.tsx) |
| **コンパイラ** | SWC Plugin |
| **スタイル** | TailwindCSS（暫定、後でデザインHTML組み込み） |
| **ルーティング** | React Router |
| **フォーム** | react-hook-form（検討中） |

### アーキテクチャ方針

**ハイブリッド型SPA**：
- Railsコントローラーがエントリポイント（初回レンダリング、認証チェック）
- React Router がクライアント側ステップ管理（ページリロードなし）
- 完了後は`window.location.href`でサーバー遷移（セッション確立、Hydraリダイレクト）

**エントリポイント分離**：
- 通常フロー（`/users/`）とSSOフロー（`/sso/`）で独立したエントリポイント
- コンポーネントは共用、login_challengeの有無で挙動を切り替え

### ディレクトリ構造

```
app/frontend/
├── entrypoints/
│   ├── users-sign-in.tsx          # 通常ログイン
│   ├── sso-sign-in.tsx            # SSOログイン
│   ├── users-sign-up.tsx          # 通常会員登録
│   └── sso-sign-up.tsx            # SSO会員登録
├── components/
│   ├── SignIn/
│   │   ├── CredentialsStep.tsx    # メール+パスワード入力
│   │   ├── VerificationStep.tsx   # 2FA認証コード入力
│   │   └── hooks/
│   │       └── useSignIn.ts
│   └── SignUp/
│       ├── EmailStep.tsx          # Step 1: メールアドレス入力
│       ├── EmailSentStep.tsx      # Step 2: メール送信完了
│       ├── PasswordStep.tsx       # Step 3: パスワード設定
│       ├── ProfileStep.tsx        # Step 4: 属性入力
│       ├── ConfirmStep.tsx        # Step 5: 確認画面
│       ├── CompleteStep.tsx       # Step 6: 完了
│       └── hooks/
│           └── useSignUp.ts
└── styles/
    └── application.css            # TailwindCSS
```

### エントリポイント例

#### 通常会員登録（users-sign-up.tsx）

```tsx
// app/frontend/entrypoints/users-sign-up.tsx
import React from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { EmailStep } from '../components/SignUp/EmailStep'
import { EmailSentStep } from '../components/SignUp/EmailSentStep'
import { PasswordStep } from '../components/SignUp/PasswordStep'
import { ProfileStep } from '../components/SignUp/ProfileStep'
import { ConfirmStep } from '../components/SignUp/ConfirmStep'
import { CompleteStep } from '../components/SignUp/CompleteStep'

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('app')
  if (!container) return

  const root = createRoot(container)

  root.render(
    <BrowserRouter>
      <Routes>
        <Route path="/users/sign_up" element={<Navigate to="/users/sign_up/email" replace />} />
        <Route path="/users/sign_up/email" element={<EmailStep />} />
        <Route path="/users/sign_up/email-sent" element={<EmailSentStep />} />
        <Route path="/users/sign_up/password" element={<PasswordStep />} />
        <Route path="/users/sign_up/profile" element={<ProfileStep />} />
        <Route path="/users/sign_up/confirm" element={<ConfirmStep />} />
        <Route path="/users/sign_up/complete" element={<CompleteStep />} />
      </Routes>
    </BrowserRouter>
  )
})
```

#### SSO会員登録（sso-sign-up.tsx）

```tsx
// app/frontend/entrypoints/sso-sign-up.tsx
import React from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { EmailStep } from '../components/SignUp/EmailStep'
import { EmailSentStep } from '../components/SignUp/EmailSentStep'
import { PasswordStep } from '../components/SignUp/PasswordStep'
import { ProfileStep } from '../components/SignUp/ProfileStep'
import { ConfirmStep } from '../components/SignUp/ConfirmStep'
import { CompleteStep } from '../components/SignUp/CompleteStep'

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('app')
  if (!container) return

  // data属性からlogin_challengeを取得
  const loginChallenge = container.getAttribute('data-login-challenge') || undefined

  const root = createRoot(container)

  root.render(
    <BrowserRouter>
      <Routes>
        <Route path="/sso/sign_up" element={<Navigate to="/sso/sign_up/email" replace />} />
        <Route path="/sso/sign_up/email" element={<EmailStep loginChallenge={loginChallenge} />} />
        <Route path="/sso/sign_up/email-sent" element={<EmailSentStep />} />
        <Route path="/sso/sign_up/password" element={<PasswordStep />} />
        <Route path="/sso/sign_up/profile" element={<ProfileStep />} />
        <Route path="/sso/sign_up/confirm" element={<ConfirmStep />} />
        <Route path="/sso/sign_up/complete" element={<CompleteStep loginChallenge={loginChallenge} />} />
      </Routes>
    </BrowserRouter>
  )
})
```

**ERB側の呼び出し：**

```erb
<!-- app/views/users/sign_up/index.html.erb -->
<div id="app"></div>
<%= vite_javascript_tag 'users-sign-up' %>

<!-- app/views/sso/sign_up/index.html.erb -->
<div id="app" data-login-challenge="<%= @login_challenge %>"></div>
<%= vite_javascript_tag 'sso-sign-up' %>
```

### Custom Hook例

```typescript
// app/frontend/components/SignUp/hooks/useSignUp.ts
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

export const useSignUp = () => {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()

  const sendEmail = async (email: string, loginChallenge?: string) => {
    setLoading(true)
    setError(null)

    try {
      const response = await fetch('/users/api/sign_up/send_email', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': getCsrfToken()
        },
        body: JSON.stringify({ email, login_challenge: loginChallenge })
      })

      const data = await response.json()

      if (data.success) {
        navigate('/users/sign_up/email-sent', { state: { token: data.token } })
      } else {
        setError(data.error || 'エラーが発生しました')
      }
    } catch (err) {
      setError('ネットワークエラーが発生しました')
    } finally {
      setLoading(false)
    }
  }

  return { sendEmail, loading, error }
}

function getCsrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
}
```

---

## バリデーション戦略

### 基本方針

**二重バリデーション戦略**：フロントエンド（UX向上）とバックエンド（セキュリティ確保）の両方で検証

```
┌─────────────────────────────────────────────────┐
│ フロントエンド (React)                            │
│ - ユーザビリティ向上（即時フィードバック）           │
│ - 基本的なフォーマット検証                        │
│ - クライアント側でできる簡易チェック               │
└─────────────────────────────────────────────────┘
                    ↓ API Request
┌─────────────────────────────────────────────────┐
│ バックエンド (Rails Form Objects)                │
│ - セキュリティ確保（全検証を実施）                 │
│ - ビジネスロジック検証                            │
│ - DB参照が必要な検証                             │
│ - フロントエンドは信頼しない                      │
└─────────────────────────────────────────────────┘
```

**重要**：バックエンドで全バリデーションを実施する。フロントエンドのバリデーションは通過してもバックエンドで弾かれる可能性がある。

---

### バックエンド：Form Objectsパターン

**採用方針**：
- 既存RP（`/Users/n/Workspace/2049/postnatal-care`）と同様のパターン
- `ActiveModel::Model`を使用した標準的なRails Form Objectsパターン
- ViewとController間のデータ受け渡しを担当
- バリデーションルールの集約

**実装イメージ（Phase 1-A）**：

```ruby
# app/forms/form.rb（基底クラス）
class Form
  include ActiveModel::Model

  # カスタムバリデーションヘルパー（必要に応じて拡張）
end

# app/forms/signup_form.rb
class SignupForm < Form
  attr_accessor :email, :password, :password_confirmation

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }
  validates :password_confirmation, presence: true
  validate :password_match

  private

  def password_match
    return if password.blank? || password_confirmation.blank?

    unless password == password_confirmation
      errors.add(:password_confirmation, 'パスワードが一致しません')
    end
  end
end

# app/forms/profile_form.rb（Phase 1-B）
class ProfileForm < Form
  attr_accessor :name, :birth_date, :phone_number

  validates :name, presence: true
  # Phase 1-Bで詳細なバリデーション追加
end
```

**Controller使用例**：

```ruby
# app/controllers/users/api/sign_up/password_controller.rb
class Users::Api::SignUp::PasswordController < ApplicationController
  def save
    @signup_form = SignupForm.new(signup_form_params)

    unless @signup_form.valid?
      render json: {
        errors: format_validation_errors(@signup_form.errors)
      }, status: :unprocessable_entity
      return
    end

    # Valkeyにパスワード保存
    CacheService.save_signup_cache(params[:token], 'password', @signup_form.password)

    render json: { success: true }
  end

  private

  def signup_form_params
    params.require(:signup_form).permit(:password, :password_confirmation)
  end

  def format_validation_errors(errors)
    errors.messages.transform_values { |v| v.first }
  end
end
```

**詳細設計**：Phase 1-A実装時に確定

---

### フロントエンド：React Hook Form + Zod（推奨）

**採用方針（Phase 2で検討）**：
- React Hook Form：フォーム状態管理
- Zod：TypeScript-firstなスキーマバリデーション
- 代替案：Yup（検討中）

**実装イメージ**：

```typescript
// types/SignupForm.ts
export interface SignupForm {
  email: string;
  password: string;
  password_confirmation: string;
}

// schemas/signupFormSchema.ts
import { z } from 'zod';

export const signupFormSchema = z.object({
  email: z.string()
    .min(1, 'メールアドレスを入力してください')
    .email('正しいメールアドレスを入力してください'),
  password: z.string()
    .min(8, 'パスワードは8文字以上で入力してください'),
  password_confirmation: z.string()
    .min(1, 'パスワード確認を入力してください')
}).refine((data) => data.password === data.password_confirmation, {
  message: 'パスワードが一致しません',
  path: ['password_confirmation']
});

// components/SignUp/PasswordStep.tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { signupFormSchema } from '../../schemas/signupFormSchema';

export const PasswordStep = () => {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<SignupForm>({
    resolver: zodResolver(signupFormSchema)
  });

  const onSubmit = async (data: SignupForm) => {
    const response = await fetch('/users/api/sign_up/save_password', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': getCsrfToken()
      },
      body: JSON.stringify({ signup_form: data })
    });

    if (!response.ok) {
      const { errors } = await response.json();
      // サーバーエラーを表示
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register('password')} type="password" />
      {errors.password && <span>{errors.password.message}</span>}

      <input {...register('password_confirmation')} type="password" />
      {errors.password_confirmation && <span>{errors.password_confirmation.message}</span>}

      <button type="submit" disabled={isSubmitting}>次へ</button>
    </form>
  );
};
```

**詳細設計**：Phase 2実装時に確定

---

### 責務分担

| 検証項目 | フロントエンド | バックエンド |
|---------|-------------|-------------|
| **必須項目チェック** | ✅ 即時フィードバック | ✅ 必須 |
| **フォーマット検証**（メール、電話番号等） | ✅ 正規表現 | ✅ 必須 |
| **文字数制限** | ✅ 即時フィードバック | ✅ 必須 |
| **パスワード一致確認** | ✅ クライアント側 | ✅ 念のため確認 |
| **メールアドレス重複チェック** | ❌ DB参照が必要 | ✅ 必須 |
| **トークン有効期限チェック** | ❌ サーバー側情報 | ✅ 必須 |
| **ビジネスルール検証** | ❌ 複雑なロジック | ✅ 必須 |
| **権限チェック** | ❌ セキュリティ | ✅ 必須 |

**原則**：
- フロントエンド：**UX向上のための補助的バリデーション**
- バックエンド：**信頼境界として全検証を実施**

---

### エラーメッセージのJSON API設計

**レスポンス形式**：

```json
// バリデーションエラー (422 Unprocessable Entity)
{
  "errors": {
    "email": "メールアドレスを入力してください",
    "password": "パスワードは8文字以上で入力してください"
  }
}

// 成功 (200 OK)
{
  "success": true,
  "redirect_to": "/users/sign_up/profile"
}
```

**実装メモ**：
- ActiveModel::Errorsを整形してJSON化
- フィールド単位のエラーメッセージ
- 国際化（I18n）対応検討

---

### 参考実装

既存RP（`/Users/n/Workspace/2049/postnatal-care`）の実装パターン：
- Form Objectsの基底クラス設計
- カスタムバリデーションヘルパー
- モデル↔フォームのマッピング機能

詳細は実装時に既存コードを参照。

---

## 段階的実装計画

### Phase 1-A: 最小限スキーマで動作確認（1-2週間）

**目的**：SSOフロー全体が動くことを早期確認

**実装内容**：

#### Week 1: DB・モデル・Services

1. **ridgepoleセットアップ**
   ```bash
   # Gemfile
   gem 'ridgepole'

   # db/Schemafile 作成
   bundle exec ridgepole --apply -E development
   ```

2. **DB・モデル（最小限）**
   - [ ] `db/Schemafile` に SignupTicket 追加（最小限カラム）
   - [ ] `db/Schemafile` に Users 拡張（最小限カラム）
   - [ ] ridgepole --apply 実行
   - [ ] SignupTicketモデル実装（基本バリデーションのみ）
   - [ ] モデル単体テスト

3. **Services層**
   - [ ] CacheService実装（機能単位：Valkeyキャッシュ操作）
     - `save_signup_cache`, `get_signup_cache`, `get_signup_data`, `delete_signup_cache`
   - [ ] SignupTicketService実装（モデル単位：トークン検証）
     - `create_ticket`, `find_valid_ticket`, `mark_as_confirmed`, `mark_as_used`
   - [ ] UserService実装（モデル単位：User作成・更新）
     - `create_from_signup`, `update_profile`
   - [ ] SignupService実装（機能単位：登録フロー統括）
     - `complete_registration`（Result Objectパターン）
   - [ ] HydraClientService実装（機能単位：Hydra連携）
     - `accept_login_request`, `accept_consent_request`
   - [ ] AuthenticationLoggerService実装（機能単位：認証ログ記録）
     - `log_user_registration`, `log_login`
   - [ ] **Service単体テスト（重点：業務ロジック完全カバー）**

#### Week 2: Controllers・View・統合テスト

4. **Controllers**
   - [ ] Users::Api::ApiController（基底、Cookie認証）
   - [ ] Users::SignUpController（親クラス、Template Method）
   - [ ] Users::Api::SignUp::EmailVerificationController（Service委譲のみ）
   - [ ] Users::Api::SignUp::PasswordController（Service委譲のみ）
   - [ ] Users::Api::SignUp::ProfileController（Service委譲のみ）
   - [ ] Users::Api::SignUp::RegistrationController（Service委譲のみ）
   - [ ] Sso::SignUpController（子クラス、Hydra連携）
   - [ ] Sso::Api::SignUp::RegistrationController（継承、オーバーライド）
   - [ ] **Controllerテスト（最小限：パラメータ受け渡し確認）**

5. **ERB版View（動作確認用）**
   - [ ] 各ステップのシンプルなフォーム
   - [ ] 最低限のスタイル

6. **統合テスト**
   - [ ] 通常登録フローのSystem Spec
   - [ ] SSOフロー中の登録のSystem Spec
   - [ ] Hydra連携のIntegration Test

**完了基準**：
- ✅ メール確認 → パスワード設定 → 登録完了が動く
- ✅ SSOログインが動く（RPにリダイレクト）
- ✅ Valkeyキャッシュが正しく動作
- ✅ 全テストがパス

**確認すべき重要ポイント**：
- Hydra accept_login_request が正しく動くか
- SignupTicket.token が全ステップで引き継がれるか
- Valkeyキャッシュ `signup:#{token}:*` が動くか
- 登録後に自動ログインできるか

---

### Phase 1-B: モデルの肉付け（1週間）

**目的**：本番で必要な属性・バリデーションを追加

**実装内容**：

1. **Schemafile更新**
   - [ ] Usersテーブルに属性追加（name、birth_date、phone_number等）
   - [ ] SignupTicketテーブルに監査カラム追加（ip_address等）
   - [ ] ridgepole --apply 実行

2. **モデル拡張**
   - [ ] Userモデルにバリデーション追加
   - [ ] SignupTicketモデルに追加機能実装
   - [ ] モデルテスト更新

3. **フォーム項目追加**
   - [ ] ProfileStep にname、birth_date等の入力項目追加
   - [ ] バリデーション強化
   - [ ] エラーメッセージ改善

4. **テスト更新**
   - [ ] 新しい属性に対応したテスト更新
   - [ ] バリデーションテスト追加

**完了基準**：
- ✅ 本番で必要な全属性が入力可能
- ✅ バリデーションが正しく動作
- ✅ 全テストがパス

---

### Phase 2: React化（デザインなし）（1-2週間）

**目的**：ERB → React SPAに置き換え、ハイブリッド型で動作確認

**実装内容**：

#### Week 1: React基盤・エントリポイント

1. **React Routerセットアップ**
   ```bash
   npm install react-router-dom
   ```

2. **エントリポイント作成（4つ）**
   - [ ] `users-sign-in.tsx` - 通常ログイン
   - [ ] `sso-sign-in.tsx` - SSOログイン
   - [ ] `users-sign-up.tsx` - 通常会員登録
   - [ ] `sso-sign-up.tsx` - SSO会員登録

3. **コンポーネント作成**
   - [ ] SignIn/CredentialsStep.tsx（メール+パスワード入力）
   - [ ] SignIn/VerificationStep.tsx（2FA認証コード）
   - [ ] SignUp/EmailStep.tsx
   - [ ] SignUp/EmailSentStep.tsx
   - [ ] SignUp/PasswordStep.tsx
   - [ ] SignUp/ProfileStep.tsx（Phase 1-Bの属性対応）
   - [ ] SignUp/ConfirmStep.tsx
   - [ ] SignUp/CompleteStep.tsx

4. **Custom Hooks実装**
   - [ ] useSignIn.ts（ログインロジック）
   - [ ] useSignUp.ts（登録ロジック）

#### Week 2: API統合・動作確認

5. **API統合**
   - [ ] fetch呼び出し実装（CSRF対応）
   - [ ] エラーハンドリング
   - [ ] ローディング状態管理
   - [ ] Rollbar連携（エラー監視）

6. **暫定デザイン**
   - [ ] TailwindCSSでシンプルなフォーム
   - [ ] 既存試作版のスタイルを流用

7. **動作確認**
   - [ ] 通常ログインフロー
   - [ ] SSOログインフロー
   - [ ] 通常登録フロー（6ステップ）
   - [ ] SSO登録フロー（login_challenge付き）
   - [ ] エラーケース（トークン期限切れ等）
   - [ ] ブラウザバック動作確認

**完了基準**：
- ✅ React SPAで全フローが動作
- ✅ React Router でURL遷移が正しく動く
- ✅ APIとの連携が正常
- ✅ Rollbarでエラー箇所が特定できる
- ✅ UXが試作版レベル

**React Router採用メリットの確認**：
- Rollbarで `/users/sign_up/password` のようにステップが特定できるか
- ブラウザバックが正しく動作するか
- 開発中に直リンクでステップアクセスできるか

---

### Phase 3: デザインHTML組み込み

**目的**：正式なデザインHTMLを適用

**実装内容**：
1. **デザインHTML受領**
   - [ ] デザイナーからHTMLファイル受け取り
   - [ ] CSSファイル受け取り
   - [ ] 画像アセット受け取り

2. **コンポーネント置き換え**
   - [ ] 各ステップのHTML適用
   - [ ] CSSクラス名調整
   - [ ] レスポンシブ対応確認

3. **最終調整**
   - [ ] アニメーション・トランジション
   - [ ] アクセシビリティ対応
   - [ ] ブラウザ互換性確認

**完了基準**：
- ✅ デザイン通りの見た目
- ✅ 全デバイスで表示確認
- ✅ アクセシビリティチェックパス

**期間**：1週間

---

### 実装順序の図解

```
Phase 1: バックエンド実装（2-3週間）
├── Week 1
│   ├── DB設計・マイグレーション
│   ├── モデル実装・テスト
│   └── Services層実装
├── Week 2
│   ├── Controllers実装
│   ├── ERB版View作成
│   └── Controllerテスト
└── Week 3
    ├── 統合テスト
    ├── Hydra連携テスト
    └── バグフィックス

    ✅ Checkpoint: Railsバックエンド完成

Phase 2: React化（1-2週間）
├── Week 4
│   ├── React Router設定
│   ├── Custom Hooks実装
│   └── コンポーネント作成
└── Week 5
    ├── API統合
    ├── エラーハンドリング
    └── 動作確認

    ✅ Checkpoint: React SPA動作確認

Phase 3: デザイン組み込み（1週間）
└── Week 6
    ├── デザインHTML適用
    ├── スタイル調整
    └── 最終テスト

    ✅ 完成
```

---

## 設定変更

### 1. Hydra設定

```yaml
# hydra.yml または環境変数
urls:
  login: https://idp.example.com/sso/sign_in      # 変更: /auth/login → /sso/sign_in
  consent: https://idp.example.com/sso/consent    # 変更: /auth/consent → /sso/consent
  logout: https://idp.example.com/sso/sign_out    # 変更: /auth/logout → /sso/sign_out

ttl:
  login_consent_request: 30m                      # 変更: 10m → 30m（会員登録対応）
```

### 2. nginx設定

```nginx
# docker/https-portal/common-config.conf

# IdP SSO機能（Hydra連携のUI）
location /sso/ {                                  # 変更: /auth/ → /sso/
    proxy_pass http://app:3000;
}

# Hydra Public API（OAuth2プロトコル）
location /oauth2/ {
    proxy_pass http://hydra:4444;
}

# その他のエンドポイント（変更なし）
location /health/ {
    proxy_pass http://hydra:4444;
}

location /.well-known/ {
    proxy_pass http://hydra:4444;
}

location /userinfo {
    proxy_pass http://hydra:4444/userinfo;
}

# IdP通常WEB機能
location / {
    proxy_pass http://app:3000;
}
```

### 3. Valkey設定（変更なし）

```ruby
# config/environments/development.rb
config.cache_store = :redis_cache_store, {
  url: ENV.fetch('VALKEY_URL', 'redis://localhost:6379/1'),
  reconnect_attempts: 3,
  timeout: 1.0,
  pool: { size: 10 }
}
```

### 4. タイムアウト設定の集約（Phase 0リファクタリング）

**目的**：各種タイムアウト設定を.envで一元管理し、保守性を向上

**対象設定**：

| 設定項目 | 環境変数 | 値 | 用途 |
|---------|---------|-----|------|
| JWT有効期限 | `JWT_EXPIRATION_MINUTES` | 30 | ✅ 既存 |
| Cookie有効期限 | 同上 | 30 | ✅ Phase 0で追加済み |
| Hydra login_consent TTL | `HYDRA_LOGIN_CONSENT_TTL_MINUTES` | 30 | ✅ Phase 0で.env化 |
| Valkeyキャッシュ有効期限 | ハードコード | 24時間 | 将来検討 |

**実装方法（Hydra TTL）**：

```bash
# .env
HYDRA_LOGIN_CONSENT_TTL_MINUTES=30
```

```yaml
# docker-compose.yml
services:
  hydra:
    environment:
      - TTL_LOGIN_CONSENT_REQUEST=${HYDRA_LOGIN_CONSENT_TTL_MINUTES:-30}m
```

```yaml
# docker/hydra/hydra.yml
ttl:
  login_consent_request: $TTL_LOGIN_CONSENT_REQUEST
```

**メリット**：
- 設定の一元管理（.envファイル1箇所で変更可能）
- 環境ごとの設定切り替えが容易（.env.local で上書き）
- 設定値の整合性確保（JWT、Cookie、Hydraチャレンジが全て30分）

---

### 5. Rails Routes

```ruby
# config/routes.rb

# ========================================
# 通常WEBユーザー機能
# ========================================
namespace :users do
  # ログイン
  get  'sign_in', to: 'sign_in#index'
  post 'sign_in', to: 'sign_in#authenticate'
  get  'sign_in/verify', to: 'sign_in#verification_form', as: :sign_in_verify
  post 'sign_in/verify', to: 'sign_in#verify'

  # 会員登録
  get 'sign_up(/*path)', to: 'sign_up#index'

  # ログアウト
  delete 'sign_out', to: 'sign_in#destroy', as: :sign_out

  # API
  namespace :api do
    namespace :sign_up do
      post 'send_email', to: 'email_verification#send'
      post 'verify_email', to: 'email_verification#verify'
      post 'save_password', to: 'password#save'
      post 'save_profile', to: 'profile#save'
      post 'complete', to: 'registration#complete'
    end
  end
end

# ========================================
# SSO機能（Hydra連携）
# ========================================
namespace :sso do
  # SSOログイン
  get  'sign_in', to: 'sign_in#index'
  post 'sign_in', to: 'sign_in#authenticate'
  get  'sign_in/verify', to: 'sign_in#verification_form'
  post 'sign_in/verify', to: 'sign_in#verify'

  # SSO会員登録
  get 'sign_up(/*path)', to: 'sign_up#index'

  # 同意画面
  get  'consent', to: 'consent#consent'
  post 'consent', to: 'consent#accept'

  # SSOログアウト
  get  'sign_out', to: 'sign_out#index'
  post 'sign_out', to: 'sign_out#accept'
end

# メール確認（namespace外）
get 'users/verify_email/:token', to: 'users/api/sign_up/email_verification#verify', as: :verify_email
```

---

## セキュリティ・認証設計

### JWT+Cookie認証

**実装方式**：
- JWTトークンをCookieに保存（httponly、secure、same_site: lax）
- サーバーサイドセッション：Valkey（Rails cache_store）

**期限設定**：

| 項目 | 現在 | 推奨 | 状態 |
|------|------|------|------|
| JWT有効期限 | 30分 | 30分 | ✅ OK |
| Railsセッション期限 | 30分 | 30分 | ✅ OK |
| **Cookie有効期限** | **未設定** | **30分** | ❌ **Phase 1-Aで修正** |

**Cookie期限の修正（Phase 1-A）**：

```ruby
# app/controllers/application_controller.rb
def set_jwt_cookie(user)
  jwt_token = JWT.encode(
    { user_id: user.id, exp: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now.to_i },
    Rails.application.secret_key_base
  )

  cookies[:auth_token] = {
    value: jwt_token,
    httponly: true,
    secure: secure_flag,
    same_site: :lax,
    expires: JwtConfig::TOKEN_EXPIRATION_MINUTES.minutes.from_now  # 追加
  }
end
```

**セキュリティ考慮事項**：
- ✅ JWT期限とCookie期限を一致させる（30分）
- ⚠️ JWT無効化機構（Phase 2以降で検討）
  - Valkeyブラックリスト方式
  - ログアウト時にトークンを無効化

---

### ログアウト戦略

**現在の設定**：`LOGOUT_STRATEGY=local`（IdPローカルログアウトのみ）

**3種類のログアウト**：

1. **IdPローカルログアウト**（現在有効）
   - IdPのセッションのみクリア
   - Cookie削除、Railsセッション削除
   - エンドポイント：`DELETE /users/sign_out`

2. **IdPグローバルログアウト**（現在無効）
   - `LOGOUT_STRATEGY=global`時に有効化
   - IdPログアウト後、Hydraのグローバルログアウトへリダイレクト
   - 全RPのセッションを一括クリア

3. **OAuth2グローバルログアウト**（実装済み）
   - RP側からHydra経由でログアウト要求
   - エンドポイント：`GET /oauth2/logout?logout_challenge=...`
   - IdPセッションをクリアし、Hydraに承認を返す

**推奨設定**：`LOGOUT_STRATEGY=local`を維持

理由：
- IdPは認証サーバーとして、ローカルセッションのみクリアすれば十分
- 各RPは独自のログアウト機能を実装
- 必要に応じてRP側からグローバルログアウトを要求する設計が推奨

---

## データモデルの特殊制約

### メールアドレスのユニーク制約がない理由

**背景**：

```
既存RPが2つ（AサイトとBサイト）
  ↓
IdPは後発リリース（会員情報統合機能として）
  ↓
初期データを両RPから移行
  ↓
同じユーザーが両方に登録済みのケースあり
  ↓
同じメールアドレスが2件存在し得る
  ↓
メールアドレスのユニーク制約を設定できない ⚠️
```

**データモデル設計**：

```ruby
# db/Schemafile
create_table "users", force: :cascade do |t|
  t.string :email, null: false  # ユニーク制約なし
  t.string :origin_rp            # 'site_a' | 'site_b' (初期データ判別用)
  t.integer :merged_into_user_id # アカウント統合後の統合先ID
  t.datetime :merged_at          # 統合日時
  # ...

  t.index :email  # 検索用インデックス（uniqueなし）
end
```

**ログイン時の処理**：

```ruby
# ログインでは固定で片側を優先（例：Aサイト由来を優先）
def find_user_for_login(email)
  # 1. Aサイト由来のユーザーを優先検索
  user = User.where(email: email, origin_rp: 'site_a', merged_at: nil).first
  return user if user.present?

  # 2. Bサイト由来のユーザーを検索
  user = User.where(email: email, origin_rp: 'site_b', merged_at: nil).first
  return user if user.present?

  # 3. 新規登録ユーザー（origin_rp: nil）
  User.where(email: email, origin_rp: nil).first
end
```

**アカウント統合機能**：
- ログイン後、ユーザー自身が操作で2つのアカウントを1つに統合
- 統合後は`merged_into_user_id`に統合先IDを記録
- 統合されたアカウントは論理削除（`merged_at`設定）
- 詳細：`notes/account-merge-feature-specification.md`

**Phase 1-Aでの対応**：
- 最小限スキーマでは`email`カラムのみ（ユニーク制約なし）
- `origin_rp`、`merged_into_user_id`等は将来の実装で追加検討

---

## 将来の拡張機能

### メールアドレス変更機能（Phase 1-B以降で検討）

**現状**：実装されていない

**実装パターン（既存RPを参考）**：

2段階トークン認証方式：
1. 現在のメールアドレスに入力トークンを送信
2. トークン検証後、新しいメールアドレスを入力
3. 新しいメールアドレスに完了トークンを送信
4. トークン検証で変更確定

**考慮事項**：
- メールアドレスのユニーク制約がないため、重複チェックのロジックが複雑
- アカウント統合機能との整合性
- Phase 1-B以降で要件を詳細化

---

### アカウント統合機能（将来実装）

**概要**：
- 2つのRPサイト（AとB）に登録していたユーザーが、IdP上で2つのアカウントを持つケース
- ユーザー操作で2つのアカウントを1つに統合

**実装方針**：
- 詳細仕様：`notes/account-merge-feature-specification.md`
- 追加認証（もう一方のアカウントでログイン）
- 属性差分のウィザード選択
- 統合実行（論理削除）

**Phase 1での対応**：
- Phase 1では実装しない（既存機能の改修が優先）
- DBスキーマに`origin_rp`、`merged_into_user_id`等を追加検討

---

### その他の拡張機能

**Phase 2以降で検討**：
- パスワード変更機能
- プロフィール編集機能（名前、電話番号等）
- アカウント設定画面
- 通知設定
- セッション管理画面（複数デバイスのログイン状態表示）

---

## テスト戦略

### テストピラミッド

```
        ▲
       ╱ ╲
      ╱   ╲
     ╱  4  ╲      4. 統合テスト（最小限）
    ╱───────╲        - System Spec（重要フローのみ）
   ╱    3    ╲     3. Controllerテスト（最小限）
  ╱───────────╲       - パラメータ受け渡し確認
 ╱      2      ╲   2. Model単体テスト（中程度）
╱───────────────╲     - バリデーション検証
      1           1. Service単体テスト（最重要・最多）
                     - 業務ロジック完全カバー
```

**テスト戦略の基本原則**：
1. **Service単体テスト（最重要）**: 業務ロジックを完全カバー
   - 高速（HTTP層なし、DB直接操作）
   - モック化しやすい
   - テストケース数: 最多

2. **Model単体テスト**: 基本バリデーションのみ
   - データ構造の検証
   - テストケース数: 中程度

3. **Controllerテスト**: パラメータ受け渡しの確認のみ
   - Service呼び出しをモック
   - テストケース数: 最小限

4. **統合テスト**: 最小限（重要フローのみ）
   - System Spec（ブラウザ操作）
   - テストケース数: 最小限

---

### 1. Service単体テスト（最重要）

業務ロジックを完全カバーし、高速に実行：

```ruby
# spec/services/signup_service_spec.rb
RSpec.describe SignupService do
  describe '.complete_registration' do
    let(:token) { 'abc123' }
    let(:request) { double('request', remote_ip: '127.0.0.1', user_agent: 'TestAgent') }
    let(:signup_ticket) { create(:signup_ticket, email: 'user@example.com', confirmed_at: Time.current) }
    let(:cached_data) { { password: 'encrypted_password', profile: { name: '山田太郎' } } }

    before do
      allow(SignupTicketService).to receive(:find_valid_ticket).with(token).and_return(signup_ticket)
      allow(CacheService).to receive(:get_signup_data).with(token).and_return(cached_data)
      allow(CacheService).to receive(:delete_signup_cache)
      allow(SignupTicketService).to receive(:mark_as_used)
      allow(AuthenticationLoggerService).to receive(:log_user_registration)
    end

    it '正常に登録できる' do
      result = SignupService.complete_registration(token: token, request: request)

      expect(result.success?).to be true
      expect(result.user).to be_present
      expect(result.user.email).to eq('user@example.com')
    end

    it '無効なトークンの場合エラーを返す' do
      allow(SignupTicketService).to receive(:find_valid_ticket).and_return(nil)

      result = SignupService.complete_registration(token: 'invalid', request: request)

      expect(result.success?).to be false
      expect(result.error_message).to eq '無効なトークン'
    end

    it 'キャッシュデータがない場合エラーを返す' do
      allow(CacheService).to receive(:get_signup_data).and_return(nil)

      result = SignupService.complete_registration(token: token, request: request)

      expect(result.success?).to be false
      expect(result.error_message).to eq 'データが見つかりません'
    end

    it 'クリーンアップ処理を実行する' do
      SignupService.complete_registration(token: token, request: request)

      expect(CacheService).to have_received(:delete_signup_cache).with(token)
      expect(SignupTicketService).to have_received(:mark_as_used).with(signup_ticket)
    end

    it 'ログ記録を実行する' do
      result = SignupService.complete_registration(token: token, request: request)

      expect(AuthenticationLoggerService).to have_received(:log_user_registration)
        .with(result.user, request)
    end
  end
end

# spec/services/signup_ticket_service_spec.rb
RSpec.describe SignupTicketService do
  describe '.find_valid_ticket' do
    it 'returns ticket when valid' do
      ticket = create(:signup_ticket, confirmed_at: Time.current, expires_at: 1.day.from_now)

      result = SignupTicketService.find_valid_ticket(ticket.token)

      expect(result).to eq ticket
    end

    it 'returns nil when ticket is expired' do
      ticket = create(:signup_ticket, confirmed_at: Time.current, expires_at: 1.day.ago)

      result = SignupTicketService.find_valid_ticket(ticket.token)

      expect(result).to be_nil
    end

    it 'returns nil when ticket is not confirmed' do
      ticket = create(:signup_ticket, confirmed_at: nil, expires_at: 1.day.from_now)

      result = SignupTicketService.find_valid_ticket(ticket.token)

      expect(result).to be_nil
    end
  end
end
```

**Serviceテストの利点**：
- 高速（HTTP層を経由しない）
- モックが容易（依存するServiceをモック化）
- 業務ロジックの詳細な検証が可能
- リファクタリングに強い

---

### 2. Model単体テスト

基本的なバリデーションの検証：

```ruby
# spec/models/signup_ticket_spec.rb
RSpec.describe SignupTicket, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:token) }
    it { should validate_uniqueness_of(:token) }
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      ticket = build(:signup_ticket, expires_at: 1.day.ago)
      expect(ticket.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      ticket = build(:signup_ticket, expires_at: 1.day.from_now)
      expect(ticket.expired?).to be false
    end
  end

  describe '#valid_for_signup?' do
    it 'returns true when confirmed and not expired' do
      ticket = build(:signup_ticket, confirmed_at: Time.current, expires_at: 1.day.from_now)
      expect(ticket.valid_for_signup?).to be true
    end

    it 'returns false when not confirmed' do
      ticket = build(:signup_ticket, confirmed_at: nil, expires_at: 1.day.from_now)
      expect(ticket.valid_for_signup?).to be false
    end

    it 'returns false when expired' do
      ticket = build(:signup_ticket, confirmed_at: Time.current, expires_at: 1.day.ago)
      expect(ticket.valid_for_signup?).to be false
    end
  end
end
```

---

### 3. Controllerテスト（最小限）

Serviceへの委譲とパラメータ受け渡しのみ確認：

```ruby
# spec/controllers/users/api/sign_up/registration_controller_spec.rb
RSpec.describe Users::Api::SignUp::RegistrationController, type: :controller do
  describe 'POST #complete' do
    let(:token) { 'abc123' }
    let(:user) { create(:user) }

    it 'SignupServiceを正しく呼び出す' do
      result = double('result', success?: true, user: user)
      expect(SignupService).to receive(:complete_registration)
        .with(token: token, request: anything)
        .and_return(result)

      post :complete, params: { token: token }

      expect(response).to have_http_status(:ok)
    end

    it 'Service失敗時にエラーを返す' do
      result = double('result', success?: false, error_message: 'エラー')
      allow(SignupService).to receive(:complete_registration).and_return(result)

      post :complete, params: { token: token }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to eq 'エラー'
    end
  end
end
```

**Controllerテストの方針**：
- Service呼び出しをモック化
- パラメータの受け渡しのみ確認
- 業務ロジックはServiceテストでカバー済み
- テストケース数を最小限に抑える

---

### 4. 統合テスト（System Spec）

重要フローのみをEnd-to-Endでテスト：

```ruby
# spec/system/user_signup_spec.rb
RSpec.describe 'User Signup', type: :system do
  describe '通常登録フロー' do
    it 'allows user to complete signup' do
      visit users_sign_up_path

      # Step 1: メールアドレス入力
      fill_in 'Email', with: 'user@example.com'
      click_button '確認メールを送信'

      # メール送信確認
      expect(page).to have_content('メールを確認してください')

      # メールリンククリック（シミュレート）
      signup_ticket = SignupTicket.last
      visit verify_email_path(token: signup_ticket.token)

      # Step 3: パスワード設定
      fill_in 'Password', with: 'password123'
      fill_in 'Password Confirmation', with: 'password123'
      click_button '次へ'

      # Step 4: 属性入力
      fill_in 'Name', with: '山田太郎'
      fill_in 'Birth Date', with: '1990-01-01'
      click_button '確認画面へ'

      # Step 5: 確認画面
      expect(page).to have_content('山田太郎')
      click_button 'アカウントを作成する'

      # 完了確認
      expect(page).to have_content('登録完了')
      expect(User.last.email).to eq('user@example.com')
    end
  end

  describe 'SSOフロー中の登録' do
    it 'redirects to Hydra after signup' do
      # login_challenge付きでアクセス
      visit sso_sign_up_path(login_challenge: 'test_challenge')

      # ... 登録フロー ...

      # 最後にHydraへリダイレクト
      expect(current_url).to include('consent_challenge')
    end
  end
end
```

### 4. Hydra連携テスト

```ruby
# spec/integration/hydra_flow_spec.rb
RSpec.describe 'Hydra OAuth2 Flow', type: :request do
  before do
    # Hydra Admin APIをモック
    allow(HydraAdminClient).to receive(:accept_login_request)
      .and_return({ 'redirect_to' => 'https://idp.example.com/sso/consent?consent_challenge=...' })
  end

  it 'completes SSO signup flow' do
    # 1. メールアドレス送信（login_challenge付き）
    post users_api_sign_up_send_email_path, params: {
      email: 'user@example.com',
      login_challenge: 'test_challenge'
    }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    token = json['token']

    # 2. Valkeyにlogin_challengeが保存されている確認
    expect(CacheService.get_signup_cache(token, 'login_challenge')).to eq('test_challenge')

    # 3-5. パスワード、属性保存...

    # 6. 登録完了
    post users_api_sign_up_complete_path, params: { token: token }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)

    # Hydra accept_login_requestが呼ばれた確認
    expect(HydraAdminClient).to have_received(:accept_login_request)
      .with('test_challenge', anything)

    # リダイレクト先がHydra
    expect(json['redirect_to']).to include('consent_challenge')
  end
end
```

---

## セキュリティ考慮事項

### 1. トークン管理

- ✅ 64文字のランダム文字列（`SecureRandom.urlsafe_base64(32)`）
- ✅ DB保存（紛失しても再発行可能）
- ✅ 有効期限24時間（自動無効化）
- ✅ 1回限りの使用（complete時に削除）
- ✅ メール確認完了フラグ（`confirmed_at`）で二重チェック

### 2. パスワード

- ✅ 最低8文字
- ✅ bcrypt暗号化
- ✅ Valkeyには暗号化済みを保存

### 3. CSRF対策

- ✅ Railsデフォルトの `protect_from_forgery`
- ✅ API呼び出しにCSRFトークン必須

### 4. キャッシュの期限管理

- ✅ Valkey: 24時間で自動削除
- ✅ UserConfirmationEmail: `expires_at`でマスター管理
- ✅ 二重の期限チェック

### 5. HTTPS必須

- ✅ 本番環境では全通信HTTPS
- ✅ Cookie: `secure: true, httponly: true, same_site: :lax`

---

## 未解決の課題・検討事項

### 1. 2FA認証との統合

**現状**：ログイン時に6桁コードによる2FA

**検討点**：登録完了直後のログインでも2FAを要求するか？

**Option A**：登録直後は2FAスキップ（メール確認で本人確認済み）
**Option B**：登録直後も2FA必須（次回ログインから適用）

**推奨**：Option A

---

### 2. 仮登録のクリーンアップ

```ruby
# lib/tasks/cleanup.rake
namespace :users do
  desc 'Delete expired signup tickets'
  task cleanup_expired_signup_tickets: :environment do
    SignupTicket.where('expires_at < ?', Time.current).destroy_all
  end
end

# cron設定
0 3 * * * cd /app && bin/rails users:cleanup_expired_signup_tickets
```

---

### 3. メール送信の非同期化

**現状**：同期送信（`deliver_now`）

**改善案**：非同期送信（`deliver_later`）

```ruby
# Sidekiq等を導入
UserMailer.email_verification(confirmation).deliver_later
```

---

## 関連ドキュメント

- `INTEGRATION.md` - RPとの連携手順
- `notes/rp-management-requirements.md` - RP管理機能要件
- `notes/api-specification.md` - API仕様
- `/Users/n/Workspace/2049/postnatal-care` - RP参考実装

---

**作成日**: 2025-10-31
**次回更新**: Phase 1実装開始時
**承認者**: （実装前に承認必要）
