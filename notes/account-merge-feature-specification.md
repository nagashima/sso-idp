# アカウント統合機能 仕様書（β版）

**ステータス**: Draft
**作成日**: 2025-10-28
**対象**: IdPサービス

---

## 1. 概要・背景

### 1.1 背景
- 新規IdPサービスで2つの既存RPサイト（Aサイト、Bサイト）にSSO提供
- 会員情報（共通属性: ユーザー名、メールアドレス等）をRPサイトにAPI提供
- パスワードはIdPで一元管理（SSO提供）
- リリース時に既存RPサイトから会員データを初期投入

### 1.2 課題
- 両方のRPサイトに登録済みだったユーザーは、IdP上で2つの別アカウントとして存在してしまう
  - 例: Aサイト会員ID=3、Bサイト会員ID=9 として別々に登録
- ユーザー体験の観点から、1つのアカウントに統合する必要がある

---

## 2. 目的

IdP上で2つのアカウントを持っているユーザーに対して、それらを1つのアカウントに統合する機能を提供する。

---

## 3. 対象ユーザー

- Aサイト、Bサイト両方に登録歴があるユーザー
- IdP上で2つの独立したアカウントを持っているユーザー

---

## 4. 機能要件

### 4.1 基本フロー
1. どちらかのRPサイト経由でIdPにログイン（例: Aユーザでログイン）
2. 統合メニューへ進む
3. もう一方のアカウント（例: Bユーザ）で追加認証
4. 統合ウィザードで属性の差分を確認・選択
5. 統合実行（最初にログインしたアカウントに寄せる）

### 4.2 認証フロー
- **通常ログイン**: メールアドレス + パスワード（1段階目）→ メールで2FA認証コード（2段階目）
- **統合用追加認証**: 通常ログインと同じUIフローを使用
  - ただし、セッション的には「ログイン」ではなく「統合対象の認証」として扱う

### 4.3 属性統合
- 両アカウント間で差異のある属性のみをウィザード形式で提示
- ユーザーが統合後の値を選択
- 選択された値を統合先アカウント（最初にログインしたアカウント）に反映

---

## 5. ユーザーフロー詳細

```
[Aユーザでログイン済み]
    ↓
[統合メニュー選択]
    ↓
[「別アカウントと統合」開始]
    ↓
[Bユーザのメールアドレス入力]
    ↓
[Bユーザのパスワード入力]
    ↓
[Bユーザのメールに2FA認証コード送信]
    ↓
[認証コード入力・検証]
    ↓
[属性差分表示・選択画面]
  - 例: 表示名、電話番号など
  - Aの値 / Bの値 から選択
    ↓
[統合確認画面]
    ↓
[統合実行]
    ↓
[完了画面]
```

---

## 6. 技術仕様案

### 6.1 技術スタック
- **フレームワーク**: Ruby on Rails
- **セッション管理**: Railsデフォルトのセッション機構

### 6.2 セッション設計

#### 通常ログイン時
```ruby
session[:user_id] = 3  # Aユーザでログイン中
```

#### 統合フロー中
```ruby
session[:user_id] = 3                    # ログイン中のユーザー（変更なし）
session[:merge_target_user_id] = 9      # 統合対象として認証済みのユーザー
session[:merge_started_at] = Time.current  # タイムアウト制御用
```

**重要**: 統合用追加認証では`session[:user_id]`を更新せず、専用のセッションキーを使用する。

### 6.3 データベース設計

#### 統合用認証テーブル（新規）
会員マスタに認証コード用カラムを追加せず、統合フロー専用の一時テーブルを作成する。

```ruby
# app/models/account_merge_verification.rb
class AccountMergeVerification < ApplicationRecord
  belongs_to :initiator_user, class_name: 'User'  # ログイン中のユーザー（統合先）
  belongs_to :target_user, class_name: 'User'     # 認証中のユーザー（統合元）
end
```

**カラム構成案**:
- `id`: primary key
- `initiator_user_id`: integer, not null（統合先ユーザー）
- `target_user_id`: integer, not null（統合元ユーザー）
- `verification_code`: string（2FA認証コード）
- `code_expires_at`: datetime（認証コード有効期限）
- `email_sent_at`: datetime（メール送信日時）
- `verified_at`: datetime（認証完了日時）
- `created_at`: datetime
- `updated_at`: datetime

**インデックス**:
- `initiator_user_id`
- `target_user_id`
- `verification_code`（検索用）

**制約**:
- `initiator_user_id != target_user_id`（自分自身との統合を防止）
- 1ユーザーが同時に複数の統合フローを開始できないよう制御

#### データライフサイクル
- 統合完了後: レコード削除
- タイムアウト後: レコード削除（バッチ処理）
- 有効期限: 作成から30分（検討中）

### 6.4 統合処理

#### 統合対象の判定条件
- 両アカウントが異なるRP由来であること（Aサイト由来 vs Bサイト由来）
- メールアドレスの一致（検討中: 必須とするか）

#### 統合実行処理
1. 統合元（`merge_target_user_id`）のデータを統合先（`user_id`）にマージ
2. 統合元のアカウントを無効化または削除（検討中）
3. 統合元に紐づいていたRP連携情報を統合先に移行
4. `session[:merge_target_user_id]`をクリア
5. 統合履歴ログの記録

---

## 7. セキュリティ考慮事項

### 7.1 認証・認可
- **タイムアウト**: 統合フローは開始から30分で無効化（検討中）
- **同一ユーザーチェック**: `initiator_user_id != target_user_id`
- **CSRF対策**: Railsのデフォルト機能を使用
- **認証コードの有効期限**: 10分（既存ログインと同様）

### 7.2 データ整合性
- トランザクション内での統合処理実行
- 統合失敗時のロールバック
- 統合履歴の監査ログ記録

### 7.3 ユーザー保護
- 統合前の確認画面表示
- 統合実行後の通知メール送信（両方のメールアドレスへ）
- 統合の取り消し機能（検討中）

---

## 8. 詳細検討項目

### 8.1 RP由来の判別方法

**課題**: どちらのRPサイト由来のユーザーかを判別する必要がある

**選択肢**:

#### 案1: 会員マスタにカラム追加
```ruby
# users テーブル
add_column :users, :origin_rp, :string  # 'site_a' | 'site_b'
# または
add_column :users, :origin_rp_id, :integer  # RP識別子
```

**メリット**:
- シンプルで直感的
- クエリが高速

**デメリット**:
- 会員マスタに統合機能専用のカラムが増える
- マイグレーション時に既存データへの値設定が必要

#### 案2: 別テーブルで管理
```ruby
# user_origins テーブル（1:1）
class UserOrigin < ApplicationRecord
  belongs_to :user
end
```

**メリット**:
- 会員マスタがクリーンに保たれる
- 将来的な拡張性（複数RP由来の履歴管理など）

**デメリット**:
- JOIN が必要になりクエリが複雑化
- 実装コストがやや高い

#### 案3: 外部キーから推測
既存の関連テーブル（例: RP連携情報テーブル）から初期登録時のRP情報を参照

**メリット**:
- 新規カラム不要

**デメリット**:
- ロジックが複雑
- データ不整合のリスク

**推奨**: **案1（会員マスタにカラム追加）**
- 統合機能は重要な基幹機能であり、パフォーマンスと明確性を優先
- `origin_rp`カラムは統合後も履歴情報として有用

---

### 8.2 統合の主体（どちらを主に残すか）

**結論**: **最初にログインした側を統合先（主）とする**

**理由**:
- ユーザーの意図を尊重（現在操作中のアカウントを維持）
- セッション管理がシンプル（`session[:user_id]`をそのまま使用）
- UX的に自然（「今使っているアカウントに、もう一つを統合する」という理解）

**実装**:
```ruby
# 統合処理
primary_user = User.find(session[:user_id])           # 統合先（最初のログイン）
secondary_user = User.find(session[:merge_target_user_id])  # 統合元（追加認証）

AccountMergeService.merge(from: secondary_user, to: primary_user)
```

---

### 8.3 統合後の残り側の扱い

**結論**: **統合元アカウントは削除（論理削除）**

**理由**:
- 同じユーザーが2つのアカウントでログインできる状態は混乱を招く
- データ整合性の観点から、統合後は1つのアカウントのみ有効とすべき

**実装方針**:

#### 論理削除（推奨）
```ruby
# users テーブル
add_column :users, :merged_into_user_id, :integer  # 統合先のユーザーID
add_column :users, :merged_at, :datetime           # 統合日時
add_column :users, :deleted_at, :datetime          # 論理削除（paranoia gem等）

# 統合処理
secondary_user.update!(
  merged_into_user_id: primary_user.id,
  merged_at: Time.current,
  deleted_at: Time.current
)
```

**メリット**:
- データの復元が可能（誤操作時のサポート対応）
- 監査証跡として有用
- 統合履歴の追跡が容易

**デメリット**:
- レコードが残り続ける（ストレージコスト）

#### 物理削除（非推奨）
完全にレコードを削除

**メリット**:
- データベースがクリーン

**デメリット**:
- 復元不可
- 監査証跡が失われる

**推奨**: **論理削除**

---

### 8.4 属性差分の比較UI実装

**要件**:
- 違いがある属性のみ表示
- ウィザード形式で項目ごとに画面遷移
- A側の値 / B側の値 から選択

**実装方針**:

#### ステップ1: 差分検出
```ruby
class AccountMergeComparator
  COMPARABLE_ATTRIBUTES = %i[
    display_name
    phone_number
    birth_date
    address
    # ...
  ].freeze

  def initialize(user1, user2)
    @user1 = user1
    @user2 = user2
  end

  def diff_attributes
    COMPARABLE_ATTRIBUTES.select do |attr|
      @user1.public_send(attr) != @user2.public_send(attr)
    end
  end
end
```

#### ステップ2: ウィザードステップ管理
```ruby
# セッションで現在のステップを管理
session[:merge_wizard_step] = 0  # 開始
session[:merge_diff_attributes] = ['display_name', 'phone_number']  # 差分のある属性
session[:merge_selections] = {}  # ユーザーの選択を保存
```

#### ステップ3: 画面遷移
```
[属性差分検出]
    ↓
[ステップ1/3: 表示名の選択]
  ラジオボタン:
  ○ Aアカウントの値: "山田太郎"
  ○ Bアカウントの値: "やまだたろう"
  [次へ]
    ↓
[ステップ2/3: 電話番号の選択]
  ラジオボタン:
  ○ Aアカウントの値: "090-1234-5678"
  ○ Bアカウントの値: "080-9876-5432"
  [戻る] [次へ]
    ↓
[ステップ3/3: 確認画面]
  選択内容の一覧表示
  [戻る] [統合実行]
```

#### ルーティング例
```ruby
# config/routes.rb
namespace :account_merge do
  resource :wizard, only: [] do
    get :step        # ウィザード各ステップの表示
    post :select     # 選択内容の保存と次ステップへ
    get :confirm     # 確認画面
    post :execute    # 統合実行
  end
end
```

#### コントローラー例
```ruby
class AccountMerge::WizardsController < ApplicationController
  def step
    @current_step = session[:merge_wizard_step]
    @attribute = session[:merge_diff_attributes][@current_step]
    @primary_value = current_user.public_send(@attribute)
    @secondary_value = merge_target_user.public_send(@attribute)
  end

  def select
    session[:merge_selections][params[:attribute]] = params[:selected_value]
    session[:merge_wizard_step] += 1

    if completed_all_steps?
      redirect_to account_merge_wizard_confirm_path
    else
      redirect_to account_merge_wizard_step_path
    end
  end
end
```

**UI考慮事項**:
- プログレスバー表示（「3項目中2項目目」など）
- 「戻る」ボタンで前ステップに戻れる
- 「スキップ」または「どちらでもない値を入力」オプションの検討
- 差分が0件の場合の処理（即座に確認画面へ）

---

## 9. その他の検討事項

### 9.1 機能面
- [ ] 統合可能条件の詳細定義（メールアドレス一致必須か等）
- [ ] 統合の取り消し機能の必要性
- [ ] 3つ以上のアカウントを持つユーザーへの対応
- [ ] 統合履歴の閲覧機能

### 9.2 UI/UX
- [ ] 統合可能なアカウントの自動検出・提案機能
- [ ] 統合メニューの配置場所
- [ ] エラーハンドリングとユーザーへのフィードバック

### 9.3 技術面
- [ ] タイムアウト時間の最適値
- [ ] 統合処理のパフォーマンス（大量データの場合）
- [ ] 統合中の別セッションからのアクセス制御
- [ ] バックグラウンドジョブ化の検討

### 9.4 運用面
- [ ] 統合失敗時のサポート対応フロー
- [ ] 統合データの監査ログ保存期間
- [ ] 古い統合認証レコードのクリーンアップバッチ

---

## 10. 参考資料

- IdP配布戦略: `notes/idp-distribution-strategy.md`
- マイグレーションガイド: `notes/migration-guide.md`

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|------------|----------|
| 2025-10-28 | 0.1 (β) | 初版作成 |
| 2025-10-28 | 0.2 (β) | 詳細検討項目を追加（RP由来判別、統合主体、削除方針、UI実装） |
