# 仮登録テーブルの実装比較：signup_tickets vs user_confirmation_emails

## 概要

産後ケア側の`user_confirmation_emails`テーブルとSSO-IdP側の`signup_tickets`テーブルの実装を比較し、設計の違いと確認すべき事項を整理。

## テーブル比較

### SSO-IdP側: signup_tickets

**スキーマ** (`db/schemas/signup_tickets.schema`):
```ruby
create_table "signup_tickets" do |t|
  t.string "email", null: false
  t.string "token", null: false
  t.datetime "expires_at", null: false
  t.datetime "confirmed_at"
  t.text "login_challenge"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["email"], name: "index_signup_tickets_on_email"          # 通常インデックス
  t.index ["expires_at"], name: "index_signup_tickets_on_expires_at"
  t.index ["token"], name: "index_signup_tickets_on_token", unique: true
end
```

**使用後の処理** (`app/services/signup_service.rb:46`):
```ruby
# 4. クリーンアップ
CacheService.delete_signup_cache(token)
SignupTicketService.mark_as_used(signup_ticket)  # ← destroy (削除)
```

### 産後ケア側: user_confirmation_emails

**スキーマ** (`db/schemas/users.schema.rb:100`):
```ruby
create_table :user_confirmation_emails do |t|
  t.string :email, null: false
  t.string :token, null: false
  t.datetime :confirmed_at, precision: nil
  t.datetime :send_at, precision: nil, null: false
  t.datetime :expires_at, precision: nil
  t.string :invite_token
  t.datetime :created_at, null: false
  t.datetime :updated_at, null: false
  t.index ["email"], name: "email", unique: true                    # ユニーク制約
  t.index ["token"], name: "token", unique: true
end
```

**使用後の処理**:
- **削除処理なし**（レコードは残したまま）

**再登録時の処理** (`app/services/user_confirmation_email_service.rb:14`):
```ruby
def _save(email)
  user_confirmation_email = UserConfirmationEmail.find_or_initialize_by(email: email)
  user_confirmation_email.email = email
  user_confirmation_email.token = RandomService.create_token          # 新トークン生成
  user_confirmation_email.send_at = Time.current
  user_confirmation_email.expires_at = Rails.configuration.app_settings[:user_confirmation_email_expires_at_hour].hour.from_now
  user_confirmation_email.confirmed_at = nil                          # クリア
  user_confirmation_email.save!                                       # 既存レコード更新
  user_confirmation_email
end
```

## 主要な違い

| 項目 | 産後ケア側 | SSO-IdP側 |
|------|-----------|----------|
| **テーブル名** | user_confirmation_emails | signup_tickets |
| **email制約** | ユニーク制約 | 通常インデックスのみ |
| **使用後の処理** | 削除しない（残す） | 削除する（destroy） |
| **再登録時** | find_or_initialize_byで既存レコード更新 | 新規レコード作成 |
| **履歴管理** | 最新の1件のみ残る | 削除されるため履歴なし |

## 重複登録防止の仕組み（両方とも同じ）

### 産後ケア側

**UsersConfirmationEmailsController#send_complete** (`app/controllers/user/users_confirmation_emails_controller.rb:20-25`):
```ruby
if UserService.is_registerd_email(@user_confirmation_email_form.email)
  # 既に登録済み → 「登録済み」メールを送る（仮登録トークン発行しない）
  UserMailer.registerd(@user_confirmation_email_form.email).deliver_now
else
  # 未登録 → 仮登録メールを送る
  UserConfirmationEmailService.save_and_send_mail(@user_confirmation_email_form.email, @after_sign_up_path)
end
```

### SSO-IdP側

**EmailController#create** (`app/controllers/sso/api/sign_up/email_controller.rb:22-24`):
```ruby
# 重複チェック
if User.exists?(email: email)
  validation_errors[:email] = ['このメールアドレスは既に登録されています']
  # → エラーを返す（仮登録トークン発行しない）
end
```

**→ 両方とも`users`テーブルで登録済みをチェックし、登録済みなら仮登録トークンを発行しない**

## ユニーク性の保証

### 当初の誤った分析

~~「産後ケア側はuser_confirmation_emailsテーブルでユニーク性を管理しているから削除しない」~~

### 正しい理解

- **両方とも`users`テーブルでユニーク性を保証している**
- 本登録完了後は`users.email`に入る
- 次回そのメールで仮登録しようとしても**usersチェックで弾かれる**
- user_confirmation_emailsに残っていても**二度と使われない**

**→ ユニーク性の保証のために残しているわけではない**

## 産後ケア側が削除しない理由（推測）

### 考えられる理由

1. **📊 履歴・統計分析用**
   - 仮登録→本登録の完了率を計測
   - マーケティング分析（どこで離脱したか等）
   - confirmed_atで完了・未完了を判別

2. **🔍 監査ログ・セキュリティ対策**
   - 不正登録試行の記録
   - いつ誰がどのメールで仮登録したかのトレース
   - セキュリティインシデント調査用

3. **🔄 再送機能・UX設計**
   - 同じメールで再度仮登録を試みた時の処理
   - 既存トークンの再利用や有効期限延長
   - エラーメッセージのカスタマイズ

4. **💾 技術的制約・運用上の理由**
   - データ保持ポリシー（法的要件など）
   - バックアップ・復旧の都合
   - 削除処理によるバグリスク回避

5. **特に理由なし**
   - 削除処理を実装していないだけ
   - ディスク容量的に問題ないので放置

## 確認すべき事項

### 産後ケア側の開発者に確認

**Q: user_confirmation_emailsテーブルのレコードを削除しない理由は？**

確認ポイント：

1. **分析・統計目的で使用していますか？**
   - 仮登録→本登録の完了率
   - confirmed_atを使った分析
   - → 使用している場合、SSO-IdP側も保持すべき

2. **監査ログ・セキュリティ対策として必要ですか？**
   - 不正登録試行の記録
   - トレーサビリティ要件
   - → 必要な場合、SSO-IdP側も保持すべき

3. **データ保持期間のルールはありますか？**
   - 法的要件（個人情報保護法等）
   - 社内ポリシー
   - → ルールがある場合、SSO-IdP側も従うべき

4. **再登録時のUXで使っていますか？**
   - 既存トークンの有効期限チェック
   - エラーメッセージの出し分け
   - → 使用している場合、SSO-IdP側も同様の実装が必要

5. **SSO-IdP側も同じ運用にすべきですか？**
   - システム間の整合性
   - 運用フローの統一
   - → 統一すべき場合、実装を合わせる必要がある

## 推奨アクション

1. **産後ケア側の開発者に上記を確認**
2. **確認結果に基づいて判断**:
   - 理由あり → SSO-IdP側も保持に変更
   - 理由なし → SSO-IdP側は現状の削除で問題なし
3. **データ保持ポリシーを文書化**
   - 削除する場合：削除タイミングとクリーンアップ処理
   - 保持する場合：保持期間と定期削除バッチの要否

## 参考ファイル

### SSO-IdP側
- `db/schemas/signup_tickets.schema`
- `app/services/signup_ticket_service.rb`
- `app/services/signup_service.rb`
- `app/controllers/sso/api/sign_up/email_controller.rb`
- `app/controllers/users/api/sign_up/email_controller.rb`

### 産後ケア側
- `/Users/n/Workspace/2049/postnatal-care/db/schemas/users.schema.rb`
- `/Users/n/Workspace/2049/postnatal-care/app/services/user_confirmation_email_service.rb`
- `/Users/n/Workspace/2049/postnatal-care/app/controllers/user/users_confirmation_emails_controller.rb`
- `/Users/n/Workspace/2049/postnatal-care/app/controllers/user/users_sign_up_controller.rb`

## 更新履歴

- 2025-11-16: 初版作成
