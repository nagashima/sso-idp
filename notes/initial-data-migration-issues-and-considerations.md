# 初期データ移行 - 問題点と検討事項

## 概要

初期データ移行と重複ユーザー対応における未解決の問題点、検討が必要な事項を整理。

## 1. 統合前のユーザーへのAPI更新制御

### 問題

重複ユーザー（A側とB側が両方存在）に対して、API経由で更新リクエストが来た場合の挙動が未定義。

### ケース1: A側への更新（priority=1）

```
POST /api/v1/users
{
  "id": 123,  // A側のユーザーID（priority=1）
  "phone_number": "090-9999-9999"
}
```

**現状の実装**:
- A側が更新される
- B側は影響なし

**問題**:
- ✅ 問題なし（A側が優先なので）

### ケース2: B側への更新（priority=2）

```
POST /api/v1/users
{
  "id": 456,  // B側のユーザーID（priority=2）
  "phone_number": "090-9999-9999"
}
```

**現状の実装**:
- B側が更新される
- A側は影響なし

**問題**:
- ⚠️ **統合前にB側を更新すると、その情報が統合時に失われる可能性**
- ⚠️ ユーザーが統合操作でA側を選んだ場合、B側の最新情報が反映されない

### ケース3: B側が論理削除されていない場合

```
# 統合操作でB側を論理削除した後
users:
  - id: 123, email: 'dup@example.com', priority: 1, deleted_at: nil
  - id: 456, email: 'dup@example.com', priority: 2, deleted_at: '2025-11-17...'

# B側（deleted_at あり）への更新リクエスト
POST /api/v1/users
{
  "id": 456,
  "phone_number": "090-9999-9999"
}
```

**現状の実装**:
```ruby
# app/controllers/api/v1/users_controller.rb

user = User.find_by(id: params[:id])
return render_not_found unless user

# 論理削除されたユーザーは404扱い
return render_not_found if user.deleted_at.present?
```

**問題**:
- ✅ 既に実装済み（論理削除済みは404）

### 検討すべき対応案

#### 案A: 現状のまま（何もしない）

**メリット**:
- シンプル

**デメリット**:
- B側への更新が統合時に失われる可能性

**適用条件**:
- 初期投入後、すぐに統合操作を促す
- API経由の更新は統合後のみ想定

#### 案B: B側への更新を禁止

```ruby
# app/controllers/api/v1/users_controller.rb

def update_user_with_id(form)
  user = User.find_by(id: params[:id])
  return render_not_found unless user
  return render_not_found if user.deleted_at.present?

  # 追加: priority=2 への更新を禁止
  if user.priority == 2
    duplicate_user = User.where(email: user.email, deleted_at: nil)
                         .where('id != ?', user.id)
                         .exists?

    if duplicate_user
      return render json: {
        error: 'Duplicate user conflict',
        message: 'このユーザーは重複しています。統合操作を先に実行してください。'
      }, status: :conflict
    end
  end

  # 通常の更新処理
  # ...
end
```

**メリット**:
- データ不整合を防げる

**デメリット**:
- 実装が複雑
- エラーハンドリングが増える

#### 案C: B側への更新をA側にも反映

```ruby
# B側への更新時、同じemailのA側にも同じ更新を適用

if user.priority == 2
  primary_user = User.where(email: user.email, priority: 1, deleted_at: nil).first
  if primary_user
    # B側とA側の両方を更新
    ActiveRecord::Base.transaction do
      user.update!(update_attrs)
      primary_user.update!(update_attrs)
    end
  end
end
```

**メリット**:
- 統合時にデータが失われない

**デメリット**:
- 非常に複雑
- 意図しない上書きのリスク

#### 推奨: 案A（現状のまま） + 運用でカバー

**理由**:
- 初期投入は一度のみ
- すぐに統合操作を促す運用
- API更新は統合後を想定

**運用**:
1. 初期データ投入直後にメンテナンスモード
2. 重複ユーザーリストを作成
3. 統合操作を促すメッセージ表示
4. 統合完了後にメンテナンス解除

## 2. 代理登録のケース

### 問題

代理登録（email=NULL, password=NULL）で作成されたユーザーのログイン方法が未定義。

### ケース: email=NULL のユーザー

```
POST /api/v1/users
{
  "last_name": "山田",
  "first_name": "太郎",
  # email なし
  # password なし
}

→ User作成: email=nil, encrypted_password=nil
```

**問題**:
- ❌ このユーザーはどうログインするのか？

### 対応案

#### 案A: 初回アクセス時にメールアドレス設定を要求

1. RP側でユーザー作成（email=NULL）
2. 初回IdPアクセス時に「メールアドレス設定」画面へ誘導
3. メールアドレス＋パスワードを設定
4. メール確認後、ログイン可能に

**課題**:
- どうやって初回アクセスを判定するのか？
- RP側のセッションをどう連携するのか？

#### 案B: 別の認証手段を提供

- 電話番号認証（SMS）
- ID/パスワード（ユーザーIDを発行）

**課題**:
- 新規実装が必要
- 仕様の複雑化

#### 案C: RP側でログイン状態を維持

- RP側でログイン済みの状態でIdPに遷移
- IdPはRP側のセッションを信頼してログイン
- SSO連携で実現

**課題**:
- セキュリティリスク
- RP側の実装依存

#### 推奨: 要件次第

- **代理登録の頻度と重要度**を確認
- **ログイン方法の運用**を明確化
- 必要に応じて案A or 案Bを実装

**暫定対応**:
- 代理登録機能は実装するが、ログインは後回し
- 統合機能の実装を優先

## 3. 初期投入ユーザーへの変更

### 問題

初期投入後、統合前のユーザーに対して、通常の会員登録フローでログインしようとした場合。

### ケース: 初期投入済みのメールアドレスで会員登録

```
# 初期投入
users:
  - id: 123, email: 'user@example.com', priority: 1, encrypted_password: nil

# 本人が会員登録フローで登録しようとする
POST /sso/api/sign_up/email
{
  "email": "user@example.com"
}
```

**現状の実装**:
```ruby
if User.exists?(email: email)
  validation_errors[:email] = ['このメールアドレスは既に登録されています']
end
```

**問題**:
- ⚠️ **本人は登録できない**
- ⚠️ しかし、初期投入時にパスワードが設定されていない可能性
- ⚠️ ログインできない状態

### 対応案

#### 案A: 初期投入時にダミーパスワードを設定

```ruby
# 初期投入時
User.create!(
  email: 'user@example.com',
  password: SecureRandom.hex(32),  # ランダムなパスワード
  priority: 1
)
```

**運用**:
- 本人は「パスワードリセット」フローでログイン
- メール送信でパスワード再設定

**メリット**:
- ✅ 既存フローで対応可能

**デメリット**:
- ⚠️ ユーザーに「パスワードリセット」を強いる
- ⚠️ UXが悪い

#### 案B: email存在チェックをスキップ（初期投入ユーザーのみ）

```ruby
# フラグを追加
t.boolean "is_imported", default: false, null: false

# 初期投入時
User.create!(
  email: 'user@example.com',
  is_imported: true,  # フラグON
  encrypted_password: nil
)

# 会員登録フロー
existing_user = User.find_by(email: email, is_imported: true)
if existing_user && existing_user.encrypted_password.blank?
  # パスワード設定画面へ誘導（新規登録として扱う）
  existing_user.update!(encrypted_password: ...)
else
  # 通常の重複チェック
  if User.exists?(email: email)
    validation_errors[:email] = ['このメールアドレスは既に登録されています']
  end
end
```

**メリット**:
- ✅ UXが良い
- ✅ 本人がスムーズに登録完了できる

**デメリット**:
- ❌ 実装が複雑
- ❌ is_imported フラグの管理

#### 推奨: 案A（ダミーパスワード）

**理由**:
- シンプル
- 既存フロー（パスワードリセット）で対応可能

**運用**:
1. 初期投入時にランダムパスワード設定
2. 本人には「初回ログイン時はパスワードリセットが必要」と案内
3. パスワードリセットフローでメール確認

## 4. パフォーマンス懸念

### 問題

重複ユーザーのログイン時、`WHERE email = ? ORDER BY priority` のパフォーマンス。

### 対策

#### 複合インデックス

```ruby
# db/schemas/users.schema
t.index ["email", "priority"], name: "index_users_on_email_and_priority"
```

**効果**:
- ✅ クエリ高速化
- ✅ インデックスのみでソート可能

#### N+1問題

```ruby
# app/services/user_login_service.rb

# 悪い例
users = User.where(email: email, deleted_at: nil).order(:priority)
user = users.first
user.created_by.name  # N+1発生

# 良い例
user = User.where(email: email, deleted_at: nil)
           .includes(:created_by)
           .order(:priority)
           .first
```

## 5. 統合漏れの監視

### 問題

重複ユーザーが統合されずに残り続ける可能性。

### 対策

#### 定期監視バッチ

```ruby
# lib/tasks/check_duplicate_users.rake

namespace :users do
  desc "重複ユーザーを検出してSlack通知"
  task check_duplicates: :environment do
    duplicates = User.where(deleted_at: nil)
                     .group(:email)
                     .having('COUNT(*) > 1')
                     .count

    if duplicates.any?
      # Slack通知
      SlackNotifier.notify("重複ユーザーが#{duplicates.size}件あります")
    end
  end
end
```

**実行**:
```bash
# cron or Heroku Schedulerで定期実行
0 9 * * * cd /app && bundle exec rake users:check_duplicates
```

## 6. NULL email でのユーザー識別

### 問題

email=NULL のユーザーが複数いる場合、どう識別するのか？

### ケース

```
users:
  - id: 1, email: nil, last_name: "山田", priority: 1
  - id: 2, email: nil, last_name: "佐藤", priority: 1
```

**問題**:
- emailでログインできない
- どうやってユーザーを特定するのか？

### 対応案

#### 案A: ユーザーIDでログイン

- 管理画面でユーザーIDを通知
- ユーザーはIDとパスワードでログイン

#### 案B: 電話番号でログイン

- phone_numberを使用
- SMS認証

#### 推奨: 要件次第

**暫定対応**:
- email=NULL のユーザーは「ログイン不可」として扱う
- 後日、メールアドレスを設定するまで待機

## 7. 統合機能の実装優先度

### 問題

統合機能の実装にどれくらい時間がかかるのか？

### タスク分解

1. **フロントエンド**（Figma参照）
   - 統合画面のUI実装
   - A側/B側の比較表示
   - 値の選択機能

2. **バックエンド**
   - POST /users/merge API
   - UserMergeService
   - トランザクション処理

3. **テスト**
   - 統合機能のテスト
   - エッジケースの確認

**見積もり**:
- フロントエンド: 2-3日
- バックエンド: 1-2日
- テスト: 1日
- **合計: 4-6日**

### 優先度

- **高**: 初期データ投入前に必須
- **リリースブロッカー**: 統合機能なしではリリース不可

## まとめ

### 即座に決定すべき事項

1. ✅ **統合前のAPI更新制御**: 案A（現状のまま）+ 運用でカバー
2. ⚠️ **代理登録のログイン方法**: 要件確認が必要
3. ✅ **初期投入ユーザーの登録**: 案A（ダミーパスワード）
4. ✅ **パフォーマンス**: 複合インデックス追加

### 検討・実装が必要な事項

5. 🆕 **統合機能**: 優先度高、4-6日で実装
6. 🆕 **重複ユーザー監視バッチ**: 実装推奨
7. ⚠️ **NULL emailのログイン**: 要件次第

### 未解決の問題

- 代理登録ユーザーのログイン方法
- NULL emailでの識別方法
- 統合機能の詳細仕様（Figma確認後）

## 更新履歴

- 2025-11-17: 初版作成（問題点と検討事項）
