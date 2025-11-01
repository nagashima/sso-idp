# RP管理機能 要件定義書（ドラフト）

**Version**: 0.1.0-draft
**Date**: 2025-10-30
**Status**: Draft（要レビュー）

---

## 📋 目次

1. [背景・目的](#背景目的)
2. [現状の課題](#現状の課題)
3. [要件](#要件)
4. [ユースケース](#ユースケース)
5. [機能一覧](#機能一覧)
6. [画面設計（ワイヤーフレーム）](#画面設計ワイヤーフレーム)
7. [データモデル](#データモデル)
8. [実装スコープ](#実装スコープ)
9. [検討事項](#検討事項)

---

## 背景・目的

### 現状

IdPでは複数のRP（Relying Party）にSSO認証を提供しており、現在は以下の方法でRPを登録している：

```bash
# スクリプト実行（ホストOS or ECS Exec）
./scripts/register-client.sh "https://rp.example.com/callback" --first-party
```

**問題点**:
1. ターミナル操作が必要（非エンジニアには困難）
2. 登録履歴が残らない（Hydra + コマンド実行ログのみ）
3. Hydra登録とRails DB登録が分離（将来的に連携が必要）
4. クレデンシャルの受け渡しが手動（コピペミス、紛失リスク）

---

## 現状の課題

### 技術的課題

| 課題 | 詳細 | 影響度 |
|------|------|--------|
| **2段階登録** | Hydra登録後、Rails DBに手動登録が必要（API認証用） | 🔴 高 |
| **履歴管理** | 登録済みRPの一覧・編集・削除が困難 | 🟡 中 |
| **監査ログ** | 誰がいつ登録したか記録なし | 🟡 中 |
| **運用負荷** | スクリプト実行にAWS CLI + ECS Exec権限が必要 | 🔴 高 |

### 運用上の課題

| 課題 | 詳細 | 影響度 |
|------|------|--------|
| **別組織との連携** | RP側は別AWS環境、別プロジェクト → クレデンシャルをメール/Slack等で送付 | 🟡 中 |
| **クレデンシャル管理** | 再発行、ローテーション、無効化の手順が不明確 | 🟡 中 |
| **IP制限** | 現在未実装（将来的に必要） | 🟢 低 |

---

## 要件

### 必須要件（Phase 1）

1. **RP登録UI**
   - ブラウザから登録可能（非エンジニアでも使える）
   - Hydra + Rails DB に自動登録
   - クレデンシャル表示（一度のみ）

2. **RP一覧・詳細表示**
   - 登録済みRPの一覧
   - 各RPの詳細情報表示（Client IDのみ、Secretは非表示）

3. **RP無効化**
   - active=false でAPI呼び出しを拒否
   - Hydra側も無効化（要検討）

4. **監査ログ**
   - 登録・更新・無効化の履歴を記録
   - 操作者、操作日時、変更内容

### オプション要件（Phase 2以降）

5. **クレデンシャルローテーション**
   - Client Secret再発行
   - 旧Secretの猶予期間設定

6. **IP制限管理**
   - 許可IPリストの登録・更新

7. **Webhook設定**
   - RP側への通知エンドポイント登録
   - 会員情報変更時の通知

8. **API Management**
   - notes/api-specification.md のAPI実装
   - RpClientテーブルでBasic認証

---

## ユースケース

### UC-01: 新規RP登録（管理者）

**アクター**: IdP管理者

**前提条件**: 管理画面にログイン済み

**フロー**:
1. 管理者が「新規RP登録」ボタンをクリック
2. フォーム入力
   - RP名（例: Production RP）
   - Callback URL（例: https://rp.example.com/callback）
   - First Party（チェックボックス）
   - 許可IP（オプション）
   - CORS Origin（オプション）
3. 「登録」ボタンクリック
4. システムが以下を実行:
   - Hydra Admin APIでクライアント登録
   - Rails DBにRpClient作成
   - 監査ログ記録
5. 成功画面表示
   - Client ID（コピーボタン）
   - Client Secret（コピーボタン、⚠️一度のみ表示）
   - .env.local形式の設定例
   - ダウンロードボタン（.envファイル）

**事後条件**: HydraとRails DBに登録完了、管理者がクレデンシャルを取得

---

### UC-02: RP一覧表示（管理者）

**アクター**: IdP管理者

**フロー**:
1. 管理者が「RP管理」メニューをクリック
2. 登録済みRPの一覧表示
   - RP名
   - Client ID
   - Callback URL
   - 登録日時
   - ステータス（有効/無効）
3. 各行に「詳細」「編集」「無効化」ボタン

---

### UC-03: RP無効化（管理者）

**アクター**: IdP管理者

**フロー**:
1. 管理者がRP一覧から「無効化」ボタンをクリック
2. 確認ダイアログ表示
3. 確認後、以下を実行:
   - Rails DB: active=false に更新
   - （検討）Hydra側も無効化？
   - 監査ログ記録
4. API呼び出しが401 Unauthorizedになる

---

### UC-04: クレデンシャル受け渡し（管理者 → RP担当者）

**アクター**: IdP管理者、RP担当者（別組織）

**フロー**:
1. IdP管理者がUC-01でRP登録
2. 成功画面から.envファイルをダウンロード
3. Slack/メール/チケットシステムでRP担当者に送付
4. RP担当者が.env.localに設定

**セキュリティ考慮**:
- ファイル暗号化（検討）
- パスワード付きZIP（検討）
- 期限付きリンク（検討）

---

## 機能一覧

### Phase 1（必須）

| 機能 | 説明 | 画面 |
|------|------|------|
| RP登録 | Hydra + Rails DBに登録 | 新規登録フォーム、成功画面 |
| RP一覧 | 登録済みRPの一覧表示 | 一覧画面 |
| RP詳細 | 個別RPの詳細情報表示 | 詳細画面 |
| RP無効化 | active=falseに設定 | 確認ダイアログ |
| 監査ログ | 操作履歴の記録 | （バックエンド） |

### Phase 2（オプション）

| 機能 | 説明 | 画面 |
|------|------|------|
| RP編集 | 名前、IP制限、Webhook URLの更新 | 編集フォーム |
| Secret再発行 | Client Secretローテーション | 再発行画面 |
| 監査ログ閲覧 | 操作履歴の表示 | ログ一覧画面 |
| API Management | notes/api-specification.md 実装 | （API） |

---

## 画面設計（ワイヤーフレーム）

### 1. RP一覧画面

```
┌─────────────────────────────────────────────────┐
│ IdP Admin - RP管理                              │
├─────────────────────────────────────────────────┤
│                                  [新規RP登録]    │
├─────────────────────────────────────────────────┤
│ RP名           │ Client ID    │ 登録日  │ 操作 │
├───────────────┼──────────────┼─────────┼──────┤
│ Production RP  │ abc123...    │ 10/20   │ [詳細] [無効化] │
│ Staging RP     │ def456...    │ 10/15   │ [詳細] [無効化] │
│ Dev RP (無効)  │ ghi789...    │ 09/30   │ [詳細] [有効化] │
└─────────────────────────────────────────────────┘
```

---

### 2. 新規RP登録フォーム

```
┌─────────────────────────────────────────────────┐
│ 新規RP登録                                      │
├─────────────────────────────────────────────────┤
│                                                 │
│ RP名 *                                          │
│ ┌─────────────────────────────────────┐         │
│ │ Production RP                       │         │
│ └─────────────────────────────────────┘         │
│                                                 │
│ Callback URL *                                  │
│ ┌─────────────────────────────────────┐         │
│ │ https://rp.example.com/callback     │         │
│ └─────────────────────────────────────┘         │
│                                                 │
│ ☑ First Party（信頼済みクライアント）           │
│                                                 │
│ 許可IP（カンマ区切り、空欄=全許可）             │
│ ┌─────────────────────────────────────┐         │
│ │ 192.168.1.10, 192.168.1.20          │         │
│ └─────────────────────────────────────┘         │
│                                                 │
│ CORS Origin（カンマ区切り）                     │
│ ┌─────────────────────────────────────┐         │
│ │ https://rp.example.com              │         │
│ └─────────────────────────────────────┘         │
│                                                 │
│               [登録]  [キャンセル]              │
└─────────────────────────────────────────────────┘
```

---

### 3. 登録成功画面

```
┌─────────────────────────────────────────────────┐
│ RP登録完了                                      │
├─────────────────────────────────────────────────┤
│ ⚠️ Client Secretは今だけ表示されます。          │
│    必ずコピーまたはダウンロードしてください。   │
│                                                 │
│ RP名: Production RP                             │
│ Callback URL: https://rp.example.com/callback   │
│                                                 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│ 📋 RP側に送付する情報                           │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                                 │
│ Client ID:                                      │
│ ┌─────────────────────────────────┐  [コピー]  │
│ │ abc123-def456-ghi789            │            │
│ └─────────────────────────────────┘            │
│                                                 │
│ Client Secret: (一度のみ表示)                   │
│ ┌─────────────────────────────────┐  [コピー]  │
│ │ secret-xyz-uvw                  │            │
│ └─────────────────────────────────┘            │
│                                                 │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│ 📝 RP側の .env.local 設定                       │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│                                                 │
│ OAUTH_CLIENT_ID=abc123-def456-ghi789            │
│ OAUTH_CLIENT_SECRET=secret-xyz-uvw              │
│                                                 │
│                      [.envファイルでダウンロード] │
│                                                 │
│               [RP一覧に戻る]                    │
└─────────────────────────────────────────────────┘
```

---

## データモデル

### DB管理方針

**ridgepole採用**：signup-during-sso-flow機能と同様にridgepoleでスキーマ管理

```bash
# スキーマ反映
bundle exec ridgepole --apply -E development --file db/Schemafile

# スキーマ確認
bundle exec ridgepole --export -E development
```

### RpClient（既存テーブル拡張）

現在の設計（notes/api-specification.md）を拡張：

```ruby
# db/Schemafile
create_table "rp_clients", force: :cascade do |t|
  # Hydra連携
  t.string :client_id, null: false
  t.string :client_secret, null: false  # TODO: ハッシュ化検討

  # 基本情報
  t.string :name, null: false
  t.text :callback_urls  # JSON配列（複数URL対応）
  t.boolean :first_party, default: false, null: false

  # セキュリティ
  t.text :allowed_ips  # カンマ区切り
  t.text :cors_origins  # カンマ区切り

  # ステータス
  t.boolean :active, default: true, null: false

  # Phase 2
  t.string :webhook_url  # 会員情報変更通知先
  t.datetime :secret_expires_at  # Secret有効期限

  t.timestamps

  t.index :client_id, unique: true
end
```

---

### RpClientAuditLog（新規テーブル）

```ruby
# db/Schemafile
create_table "rp_client_audit_logs", force: :cascade do |t|
  t.references :rp_client, null: false, foreign_key: true
  t.references :admin_user, null: true  # 操作者（要AdminUserテーブル）

  t.string :action, null: false  # 'create', 'update', 'deactivate', 'rotate_secret'
  t.json :changes  # 変更内容（before/after）
  t.string :ip_address  # 操作元IP

  t.timestamps
end
```

---

## 実装スコープ

### Phase 1: 基本機能（1-2週間）

#### Step 1: モデル作成
- [ ] `db/Schemafile` に RpClient 追加
- [ ] `db/Schemafile` に RpClientAuditLog 追加
- [ ] ridgepole --apply 実行
- [ ] RpClient モデル実装
- [ ] RpClientAuditLog モデル実装
- [ ] バリデーション実装
- [ ] モデルテスト

#### Step 2: Controller実装
- [ ] Admin::RpClientsController
  - [ ] new / create（登録）
  - [ ] index（一覧）
  - [ ] show（詳細）
  - [ ] deactivate（無効化）
- [ ] Hydra Admin API連携

#### Step 3: View実装
- [ ] 一覧画面
- [ ] 新規登録フォーム
- [ ] 成功画面（クレデンシャル表示）
- [ ] 詳細画面

#### Step 4: 認証・認可
- [ ] 管理者認証（devise等）
- [ ] 管理画面アクセス制限

#### Step 5: 動作確認
- [ ] 新規登録フロー
- [ ] 一覧・詳細表示
- [ ] 無効化
- [ ] 監査ログ記録

---

### Phase 2: 拡張機能（必要に応じて）

- [ ] RP編集機能
- [ ] Client Secret再発行
- [ ] 監査ログ閲覧画面
- [ ] API Management（notes/api-specification.md）
- [ ] Webhook実装

---

## 検討事項

### 1. 管理者認証

**選択肢**:
- A. Devise + Admin名前空間
- B. 既存User + admin権限
- C. Basic認証（簡易版）

**推奨**: A（将来的に拡張しやすい）

---

### 2. Client Secret管理

**現状**: 平文でDB保存

**検討**:
- ハッシュ化（bcrypt）→ Hydraとの照合が困難
- 暗号化（rails credentials）→ 複号が必要
- 平文維持 → DBアクセス制限でカバー

**推奨**: 当面は平文維持、Phase 2で暗号化検討

---

### 3. Hydra側の無効化

**問題**: RailsでRP無効化時、Hydra側も無効化すべきか？

**選択肢**:
- A. Rails側のみ（API認証で拒否）→ OIDC flowは動作
- B. Hydra側も無効化 → OIDC flowも拒否

**推奨**: A（シンプル、API認証で制御十分）

---

### 4. クレデンシャル受け渡しのセキュリティ

**現状**: .envファイルダウンロード → 手動送付

**拡張案**:
- 期限付きリンク（1時間で無効化）
- パスワード付きZIP
- 暗号化ファイル（GPG等）

**推奨**: Phase 1は現状維持、Phase 2で拡張

---

### 5. register-client.sh の扱い

**選択肢**:
- A. 管理画面実装後も併存（運用柔軟性）
- B. 管理画面に統一（スクリプト廃止）

**推奨**: A（緊急時やCI/CD用にスクリプトも残す）

---

## 次のアクション

### このドラフトをレビュー後

1. **要件確定**
   - 必須要件の追加・削除
   - Phase 1スコープの最終化

2. **技術設計**
   - ルーティング設計
   - Controller/Model詳細設計
   - View設計（実際のHTML）

3. **実装開始**
   - Step 1（モデル作成）から

---

**作成日**: 2025-10-30
**次回更新**: レビュー後
**関連ドキュメント**: notes/api-specification.md, tmp/session-handoff-rp-api.md
