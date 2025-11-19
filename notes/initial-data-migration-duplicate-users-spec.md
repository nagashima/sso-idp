# 初期データ移行と重複ユーザー対応仕様

## 概要

2つのRP（Relying Party）から既存会員データをIdPに統合する際の仕様。

**主要な課題**:
- 同じメールアドレスのユーザーが両RPに存在する可能性
- 現状のDB制約（`users.email`にユニーク制約）では初期投入時にエラー
- 代理登録ではメールアドレス・パスワードがない場合がある

## 基本方針

1. **初期投入時のみメールアドレス重複を許可**
   - 2RPからのデータ取り込み時のみ
   - リリース以降は重複を許さない

2. **重複ユーザーには統合機能を提供**
   - 画面イメージ: Figmaで提供済み
   - どちらのレコードの値を採用するか選択
   - 統合後は1レコードに集約

3. **優先度でユーザーを同定**
   - ログイン時: priority最小のレコードを使用
   - 統合時: priority最小を主体（primary）として扱う

4. **API経由の代理登録でemail/password NULLを許可**
   - メールアドレスの受信確認ができない場合
   - 後日、本人がメールアドレスを設定

## DB変更

### 1. users.email のユニーク制約削除

#### 現状

```ruby
# db/schemas/users.schema:70
t.index ["email"], name: "index_users_on_email", unique: true
```

#### 変更後

```ruby
# db/schemas/users.schema:70
t.index ["email"], name: "index_users_on_email"  # unique削除
```

**Ridgepoleで反映**:
```bash
docker-compose exec app rake ridgepole:apply
```

### 2. users.priority カラム追加

```ruby
# db/schemas/users.schema

create_table "users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
  t.string "email"
  t.integer "priority", default: 1, null: false, comment: "優先度（小さい方が優先、重複ユーザーのログイン判定に使用）"
  # ... 他のカラム

  # インデックス
  t.index ["email"], name: "index_users_on_email"  # unique削除
  t.index ["email", "priority"], name: "index_users_on_email_and_priority"
end
```

**カラムの意味**:
- `priority=1`: A側（優先RP）のユーザー、または新規ユーザー
- `priority=2`: B側（次点RP）のユーザー
- デフォルト: 1

## アプリケーション側の制御

### 1. 会員登録フロー（SSO/通常）

**変更なし** - 引き続き重複チェックを実施

```ruby
# app/controllers/sso/api/sign_up/email_controller.rb
# app/controllers/users/api/sign_up/email_controller.rb

if User.exists?(email: email)
  validation_errors[:email] = ['このメールアドレスは既に登録されています']
end
```

**動作**:
- 既に存在するメールアドレスでは登録不可
- リリース以降は重複が発生しない仕組み

### 2. ログイン処理

**priority最小のレコードを使用**

```ruby
# app/services/user_login_service.rb

class UserLoginService
  def self.find_user_by_email(email)
    User.where(email: email, deleted_at: nil)
        .order(:priority)
        .first
  end
end
```

**動作**:
- 重複ユーザー: `priority=1` のA側を取得
- B側のみのユーザー: `priority=2` の1件を取得（問題なし）
- 新規ユーザー: `priority=1` の1件を取得

**使用例**:
```ruby
# app/controllers/sessions_controller.rb

user = UserLoginService.find_user_by_email(params[:email])
if user&.authenticate(params[:password])
  # ログイン成功
end
```

### 3. API経由のユーザー作成（POST /api/v1/users）

#### 3-1. email/password NULLを許可

**実装方針**: Concern側を条件付きバリデーションに変更し、API Formでオーバーライド

**Concern変更**:
```ruby
# app/forms/concerns/validatable_user_password.rb

# パスワード必須を条件付きに
validates :password,
          presence: { message: 'パスワードを入力してください' },
          length: { minimum: 8, maximum: 128, message: 'パスワードは8文字以上で入力してください' },
          if: :require_password?

validates :password_confirmation,
          presence: { message: 'パスワード（確認のため再入力）を入力してください' },
          if: :require_password?

# デフォルトは必須（WEB版会員登録用）
def require_password?
  true
end
```

**API Form変更**:
```ruby
# app/forms/api/v1/user_form.rb

# email: すでに allow_blank: true 設定済み（変更不要）
validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

# password: API経由では任意
def require_password?
  false  # Concernのメソッドをオーバーライド
end
```

**メリット**:
- WEB版会員登録（Users::PasswordForm）では引き続きpassword必須
- API経由（Api::V1::UserForm）のみemail/password任意
- Concernを共有しつつ、分岐が明示的

#### 3-2. 重複チェック（emailありの場合のみ）

```ruby
# app/controllers/api/v1/users_controller.rb

# ID未指定の新規作成時
if params[:id].blank?
  # emailがある場合のみ重複チェック
  if params[:email].present? && User.exists?(email: params[:email])
    return render json: {
      error: 'Email already exists',
      message: 'このメールアドレスは既に登録されています'
    }, status: :conflict
  end
end
```

**動作**:
- email指定あり: 重複チェック（既存通り）
- email=NULL: チェックスキップ（新規：代理登録）

### 4. 初期データ投入

```ruby
# lib/tasks/import_initial_users.rake

namespace :import do
  desc "RP-AとRP-Bの初期ユーザーデータを投入"
  task initial_users: :environment do
    # RP-A（優先側）からのインポート
    csv_a.each do |row|
      User.create!(
        email: row[:email],
        priority: 1,  # A側は1
        # ... 他の属性
      )
    end

    # RP-B（次点側）からのインポート
    csv_b.each do |row|
      User.create!(
        email: row[:email],
        priority: 2,  # B側は2（重複してなくても2）
        # ... 他の属性
      )
    end
  end
end
```

**実行**:
```bash
docker-compose exec app bundle exec rake import:initial_users
```

**結果**:
- A側: priority=1
- B側: priority=2（重複の有無に関わらず）
- 重複しているメールアドレスは2レコード存在

## 統合機能

**詳細仕様**: `notes/account-merge-feature-specification.md` を参照

### 基本フロー（ウィザード形式）

1. **A側でログイン**
   - 重複ユーザーはA側（priority=1）でログイン

2. **統合メニュー選択**
   - 「別アカウントと統合」を選択

3. **B側アカウントで追加認証**
   - B側のメールアドレス入力
   - B側のパスワード入力
   - B側のメールに2FA認証コード送信
   - 認証コード入力・検証

4. **属性差分のウィザード形式選択**
   - 違いがある属性のみ表示
   - 属性ごとに画面遷移（1属性ずつ）
   - ラジオボタンでA側/B側の値を選択
   - 例:
     ```
     [ステップ1/3: 電話番号の選択]
     ○ Aアカウントの値: 090-1111-2222
     ○ Bアカウントの値: 090-3333-4444
     [戻る] [次へ]

     [ステップ2/3: 住所の選択]
     ○ Aアカウントの値: 東京都...
     ○ Bアカウントの値: 神奈川県...
     [戻る] [次へ]
     ```

5. **確認画面**
   - 選択内容の一覧表示
   - [戻る] [統合実行]

6. **統合実行**
   - A側レコードを更新（選択された値で上書き）
   - B側レコードを論理削除
   - 完了画面表示

### セッション管理

```ruby
session[:user_id] = 123                    # A側（統合先、ログイン中）変更なし
session[:merge_target_user_id] = 456      # B側（統合元、追加認証済み）
session[:merge_started_at] = Time.current # タイムアウト制御用
session[:merge_wizard_step] = 0           # 現在のウィザードステップ
session[:merge_diff_attributes] = ['phone_number', 'home_postal_code']  # 差分属性
session[:merge_selections] = { phone_number: 'from_secondary', ... }    # 選択内容
```

**重要**: 統合用追加認証では`session[:user_id]`を更新せず、専用のセッションキーを使用。

### 統合処理（実装イメージ）

```ruby
# app/services/account_merge_service.rb

def self.merge(from:, to:, selections:)
  ActiveRecord::Base.transaction do
    # 1. A側（to）を更新（選択された値で上書き）
    selections.each do |attribute, source|
      if source == 'from_secondary'
        to[attribute] = from[attribute]
      end
      # from_primaryの場合は何もしない（そのまま）
    end
    to.save!

    # 2. B側（from）を論理削除
    from.update!(
      merged_into_user_id: to.id,
      merged_at: Time.current,
      deleted_at: Time.current
    )

    # 3. user_relying_partiesもマージ（TBD）

    # 4. セッションクリア
    # session[:merge_target_user_id]などをクリア
  end
end
```

**結果**:
- A側: 統合後の値で更新
- B側: 論理削除（deleted_at, merged_into_user_id, merged_at設定）
- 重複解消

### 新規実装が必要なもの

1. **フロントエンド**
   - 統合メニュー画面
   - B側追加認証画面（既存ログイン画面を流用）
   - 属性差分ウィザード画面（属性ごとに遷移）
   - 確認画面
   - 完了画面

2. **バックエンド**
   - `AccountMergeVerification` モデル（2FA認証管理）
   - `AccountMerge::WizardsController`（ウィザード制御）
   - `AccountMergeService`（統合処理）
   - `AccountMergeComparator`（差分検出）

3. **DB**
   - `account_merge_verifications` テーブル
   - `users.merged_into_user_id` カラム
   - `users.merged_at` カラム

## API仕様の変更

### openapi.yaml

#### UserCreateRequestスキーマ

**変更前**:
```yaml
required:
  - email
  - password
  - password_confirmation
  - last_name
  - first_name
  # ...
```

**変更後**:
```yaml
required:
  - last_name
  - first_name
  - last_kana_name
  - first_kana_name
  # email, password は required から削除
```

#### emailプロパティ

```yaml
email:
  type: string
  format: email
  nullable: true
  description: |
    メールアドレス（任意）

    通常の会員登録では必須だが、API経由の代理登録では省略可能。
    省略した場合、後で PATCH で設定可能。
  example: user@example.com
```

#### passwordプロパティ

```yaml
password:
  type: string
  nullable: true
  description: |
    パスワード（任意、8文字以上）

    通常の会員登録では必須だが、API経由の代理登録では省略可能。
    省略した場合、ユーザーは初回ログイン時にパスワードリセットフローを経由。
  example: password123
```

#### 409 Conflict（email重複）

**descriptionとexample**:
```yaml
'409':
  description: email重複（ID未指定時）
  content:
    application/json:
      schema:
        $ref: '#/components/schemas/Error'
      examples:
        emailConflict:
          summary: メールアドレス重複
          value:
            error: Email already exists
            message: このメールアドレスは既に登録されています
```

**注意**:
- phone_number重複エラーは削除済み（電話番号はユニーク制約なし）

## 実装パターン（暫定推奨）

### パターンA: 後処理なし（シンプル）

**初期投入**:
- A側: `priority=1`
- B側: `priority=2`（重複の有無に関わらず）

**ログイン処理**:
```ruby
User.where(email: email, deleted_at: nil).order(:priority).first
```

**メリット**:
- ✅ 超シンプル（後処理スクリプト不要）
- ✅ SQLだけで完結

**デメリット**:
- ⚠️ B側のみのユーザーも `priority=2`（見た目）
  - 動作に影響なし

### パターンB: 初期投入後に後処理（最適化版）

**初期投入後の後処理**:
```ruby
# 重複していないB側ユーザーのpriorityを1に変更
duplicate_emails = User.where(deleted_at: nil)
                       .group(:email)
                       .having('COUNT(*) > 1')
                       .pluck(:email)

User.where(deleted_at: nil)
    .where(priority: 2)
    .where.not(email: duplicate_emails)
    .update_all(priority: 1)
```

**メリット**:
- ✅ データとして綺麗

**デメリット**:
- ❌ 後処理スクリプト必要

**チームへの提案**: 暫定パターンA、必要に応じてパターンB

## データフロー

### 初期投入時

```
【投入前】
users: 0件

【RP-A投入後】
users:
  - id: 1, email: 'user1@example.com', priority: 1  # A側のみ
  - id: 2, email: 'dup@example.com', priority: 1    # A側（重複予定）

【RP-B投入後】
users:
  - id: 1, email: 'user1@example.com', priority: 1  # A側のみ
  - id: 2, email: 'dup@example.com', priority: 1    # A側（重複）
  - id: 3, email: 'dup@example.com', priority: 2    # B側（重複）★
  - id: 4, email: 'user2@example.com', priority: 2  # B側のみ
```

### ログイン時

```
email='dup@example.com' でログイン
→ WHERE email='dup@example.com' ORDER BY priority
→ id: 2 (priority=1) を取得
```

### 統合後

```
【統合実行: id:2 と id:3 をマージ】
users:
  - id: 1, email: 'user1@example.com', priority: 1
  - id: 2, email: 'dup@example.com', priority: 1    # 統合後の値
  - id: 3, email: 'dup@example.com', priority: 2, deleted_at: '2025-11-17...'  # 論理削除
  - id: 4, email: 'user2@example.com', priority: 2

【統合後のログイン】
email='dup@example.com' でログイン
→ WHERE email='dup@example.com' AND deleted_at IS NULL ORDER BY priority
→ id: 2 のみ（id: 3は除外）
```

## テストケース

### 1. 重複なし（通常ケース）

```ruby
it "重複がない場合、該当ユーザーを返す" do
  user = create(:user, email: 'single@example.com', priority: 1)

  result = UserLoginService.find_user_by_email('single@example.com')

  expect(result).to eq(user)
end
```

### 2. 重複あり（priority最小を返す）

```ruby
it "重複がある場合、priority最小のユーザーを返す" do
  user_a = create(:user, email: 'dup@example.com', priority: 1)
  user_b = create(:user, email: 'dup@example.com', priority: 2)

  result = UserLoginService.find_user_by_email('dup@example.com')

  expect(result).to eq(user_a)
end
```

### 3. email=NULLでの作成

```ruby
it "email=NULL でユーザーを作成できる" do
  post '/api/v1/users',
       params: {
         last_name: '山田',
         first_name: '太郎',
         # email なし
       },
       headers: { 'Authorization' => auth_header },
       as: :json

  expect(response).to have_http_status(:created)
  user = User.last
  expect(user.email).to be_nil
end
```

### 4. email重複エラー

```ruby
it "重複emailの場合、409 Conflictが返される" do
  create(:user, email: 'duplicate@example.com')

  post '/api/v1/users',
       params: { email: 'duplicate@example.com', ... },
       headers: { 'Authorization' => auth_header },
       as: :json

  expect(response).to have_http_status(:conflict)
end
```

### 5. email=NULL の重複（OK）

```ruby
it "email=NULL の場合、重複しても作成できる" do
  create(:user, email: nil, priority: 1)

  post '/api/v1/users',
       params: { ... },  # email なし
       headers: { 'Authorization' => auth_header },
       as: :json

  expect(response).to have_http_status(:created)
end
```

## 影響範囲まとめ

### DB変更

1. ✅ `db/schemas/users.schema`
   - email のユニーク制約削除
   - priority カラム追加（default: 1）
   - 複合インデックス追加（email, priority）

### アプリケーション変更

2. ✅ `app/forms/concerns/validatable_user_password.rb`
   - password バリデーションを条件付きに変更（require_password?）

3. ✅ `app/forms/api/v1/user_form.rb`
   - require_password? をオーバーライド（API経由では任意）
   - email は元から allow_blank: true

4. ✅ `app/controllers/api/v1/users_controller.rb`
   - email重複チェック条件追加（emailありの場合のみ）

5. ✅ `app/services/user_login_service.rb`
   - 新規作成 or 既存修正
   - `order(:priority).first` で取得

6. ✅ `docs/openapi.yaml`
   - email/password を required から削除
   - nullable: true 追加

### 新規実装

7. 🆕 `lib/tasks/import_initial_users.rake`
   - 初期データ投入スクリプト

8. 🆕 統合機能
   - フロントエンド: 統合画面（Figma参照）
   - バックエンド: POST /users/merge API
   - サービス: UserMergeService

9. 🆕 `spec/services/user_login_service_spec.rb`
   - ログイン処理のテスト

10. 🆕 `spec/requests/api/v1/users_spec.rb`
   - email=NULL、重複系のテスト追加

### 運用

11. ✅ `rake ridgepole:apply`
    - スキーマ適用

12. ✅ `rake import:initial_users`
    - 初期データ投入

13. ⚠️ パターンBの場合のみ
    - `rake users:normalize_priority`
    - 後処理スクリプト実行

## 注意事項

- **DB制約削除**: 慎重に実施（本番環境への影響大）
- **段階的リリース**: Phase分けて実装・リリース
- **ユーザー案内**: 統合操作の促進メッセージ
- **定期監視**: 統合漏れチェック（重複email検出バッチ）

## 更新履歴

- 2025-11-17: 初版作成（総合仕様）
