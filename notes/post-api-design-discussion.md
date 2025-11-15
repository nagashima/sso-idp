# POST系API設計の検討事項

## 前提：構想

- **POST /api/v1/users**: 全カラム指定でUpsert（Update or Insert）
- **PATCH /api/v1/users/:id**: 対象カラムのみ指定でUpdate

---

## 一般的なパターン

### 1. 厳格なRESTful（従来型）

```
POST /users         → 新規のみ、存在すればエラー（409 Conflict）
PUT /users/:id      → 全体更新、全カラム必須
PATCH /users/:id    → 部分更新、差分のみ
```

**特徴：**
- クライアントが事前にGETして存在確認し、POST/PUT/PATCHを使い分ける必要がある
- 厳格だが、クライアント側の実装負担が大きい

### 2. Upsert（現代的）

```
POST /users         → なければ作成、あれば更新（全カラム）
PATCH /users/:id    → 部分更新（差分のみ）
```

**特徴：**
- RPが楽、一般的になってきている
- 事前のGETが不要

### 3. 本プロジェクトの推奨

```
POST /api/v1/users （Upsert）
- emailまたはphone_numberで既存ユーザー判定
- なければ新規作成 → created_by設定
- あれば全体更新 → updated_by設定
- 全カラム送信を想定（任意カラムはnull許可）

PATCH /api/v1/users/:id （部分更新）
- IDで指定
- 送られたフィールドのみ更新
- updated_by設定
```

---

## 検討が必要な問題点

### PATCH /api/v1/users/:id
**問題なし：** URLのIDで対象ユーザーを特定、差分のみ更新

### POST /api/v1/users（Upsert）の既存ユーザー判定方法

POST時に「新規作成」か「既存ユーザー更新」かをどう判定するか？

#### ケース1: リクエストにIDを含める場合

```json
POST /api/v1/users
{
  "id": 123,
  "email": "user@example.com",
  "last_name": "山田",
  ...
}
```

**選択肢：**

**A案: ID存在チェック厳格**
- ID=123が存在 → 更新
- ID=123が存在しない → **404エラー**（PATCHと同じ挙動）

**B案: ID指定は参考程度**
- ID=123が存在 → 更新
- ID=123が存在しない → **IDを無視して新規作成**（自動採番）

#### ケース2: リクエストにIDを含めない場合

```json
POST /api/v1/users
{
  "email": "user@example.com",
  "last_name": "山田",
  ...
}
```

**選択肢：**

**A案: 常に新規作成**
- 無条件で新規作成
- emailが既存と重複していればエラー（DB制約違反）

**B案: emailで既存ユーザー検索**
- email="user@example.com"のユーザーが存在 → 更新
- 存在しない → 新規作成
- **問題:** emailが空の場合はどうする？

**C案: phone_numberで既存ユーザー検索**
- phone_number="09012345678"のユーザーが存在 → 更新
- 存在しない → 新規作成
- **問題:** phone_numberが空の場合はどうする？

**D案: 専用キーで判定カラムを指定**
```json
{
  "lookup_by": "email",  // または "phone_number"
  "email": "user@example.com",
  ...
}
```
- 柔軟だが、APIが複雑になる

**E案: emailとphone_numberの両方で判定**
- emailまたはphone_numberのいずれかが一致すれば更新
- どちらも一致しなければ新規作成
- **問題:** 複数ヒットする可能性（email一致とphone_number一致が別ユーザー）

---

## 推奨案

```
POST /api/v1/users
- id指定あり → そのIDで更新、存在しなければ404エラー
- id指定なし → emailで既存ユーザー検索
  - email一致するユーザーが存在 → 更新
  - 存在しない → 新規作成
  - emailが空の場合 → 新規作成（emailはユニーク制約だがnullable）
```

**理由：**
- RPが「このemailのユーザー情報を最新化したい」という意図で使いやすい
- 重複登録を防げる
- シンプル

---

## 決定すべきこと

1. **POST時のID指定ありの挙動**
   - A案（厳格）か B案（柔軟）か？

2. **POST時のID指定なしの挙動**
   - A案（常に新規）、B案（email判定）、C案（phone判定）、D案（専用キー）、E案（両方判定）のどれか？

3. **判定キーが空の場合の挙動**
   - 新規作成？エラー？

4. **複数ヒットの可能性**
   - emailとphone_numberで異なるユーザーがヒットする場合の処理

---

## 補足：created_by / updated_by の設定

- **新規作成時:** `created_by` にリクエスト元RPのIDを設定
- **更新時:** `updated_by` にリクエスト元RPのIDを設定
- **WEB/SSO登録:** どちらもNULL

---

## 次のステップ

チームで上記の選択肢を議論し、仕様を確定する。
確定後、POST /api/v1/users と PATCH /api/v1/users/:id を実装。
