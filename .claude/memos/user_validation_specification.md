# Userバリデーション実装仕様書

**作成日**: 2025-11-12
**対象**: ユーザー登録・更新API（WEB版、SSO版、RP向けAPI共通）

---

## 目的

- WEB版会員登録 (`/users/api/sign_up/profile`)
- SSO版会員登録 (`/sso/api/sign_up/profile`)
- 会員情報変更 (`/users/api/profile`) ※未実装
- RP向けAPI (`/api/v1/users`, `/api/v1/users/:id`) ※未実装

上記すべてのAPIで共通利用できるバリデーションロジックを、**Form Objectsパターン**で実装する。

---

## バリデーション要件一覧

### 1. 基本情報

| # | フィールド | DBカラム | 必須 | 入力形式 | 最大文字数 | 文字種 | 制限内容 | 備考 |
|---|-----------|---------|-----|---------|----------|--------|---------|------|
| 1 | メールアドレス | `email` | ● | 文字列 | 255 | 半角英数字/記号 | `/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i`<br>※RFC違反も許可（病児保育と合わせる） | 登録時はトークン経由で取得<br>**全角→半角変換処理あり** |
| 2 | パスワード | `encrypted_password` | ● | 文字列 | 255 | 半角 | - 使用文字は特に制限なし（スペースのみはNG）<br>- 病児保育の新仕様と揃える | 8文字以上<br>確認用パスワードとの一致チェック |
| 3 | 姓 | `last_name` | ● | 文字列 | 255 | 制限なし | - | - |
| 4 | 名 | `first_name` | ● | 文字列 | 255 | 制限なし | - | - |
| 5 | ミドルネーム有無 | `has_middle_name` | ● | チェックボックス | - | - | - | tinyint(1), 0 or 1 |
| 6 | ミドルネーム | `middle_name` | △ | 文字列 | 255 | 制限なし | ミドルネームありのときは**空欄は許可しない** | `has_middle_name=1`の場合のみ必須 |
| 7 | 姓（ふりがな） | `last_kana_name` | ● | 文字列 | 255 | ひらがな、長音記号 | `/\A[ぁ-んー]+\z/` | - |
| 8 | 名（ふりがな） | `first_kana_name` | ● | 文字列 | 255 | ひらがな、長音記号 | `/\A[ぁ-んー]+\z/` | - |
| 9 | 生年月日 | `birth_date` | ● | プルダウン | - | - | - すべての項目選択必須<br>- 年：1900～今年<br>- 月：1～12<br>- 日：1～31<br>- 日付の整合性（2/30不可等）<br>- 未来日不可 | デフォルト値: 1980-01-01 |
| 10 | 性別 | `gender_code` | ● | ラジオボタン | - | - | - 選択肢（男性/女性/指定なし/その他）<br>- 「その他」選択時、記入欄発生 | 1=男性, 2=女性, 3=指定しない, 4=自由記述 |
| - | 性別（自由記述） | `gender_text` | △ | 文字列 | - | - | - | `gender_code=4`の場合のみ使用 |
| 11 | 電話番号 | `phone_number` | ● | 文字列 | 255 | 制限なし | - 形式バリデーションなし（`presence: true`のみ）<br>- 産後ケアRPと同じ仕様 | **正規化処理あり**（SSO-IdPで追加）<br>- 全角数字→半角<br>- 全角ハイフン・長音記号→半角ハイフン<br>- スペース・括弧削除<br>- 保存形式：数字とハイフン（両方半角） |

### 2. 住所情報（自宅）

| # | フィールド | DBカラム | 必須 | 入力形式 | 最大文字数 | 文字種 | 制限内容 | 備考 |
|---|-----------|---------|-----|---------|----------|--------|---------|------|
| 12 | 住所手動入力有無 | `home_is_address_selected_manually` | ● | - | - | - | - | tinyint(1), 0=自動, 1=手動 |
| 13 | 郵便番号 | `home_postal_code` | △ | 文字列 | 8 | 半角数字、ハイフン | - 7桁の数字または「000-0000」の形式で入力<br>- DB保存時はハイフン除去 | **自動入力モード（`home_is_address_selected_manually=0`）の場合のみ必須**<br>**全角→半角変換処理あり** |
| 14 | 都道府県コード | `home_prefecture_code` | ● | - | - | - | - | - |
| 15 | 市区町村コード | `home_master_city_id` | ● | - | - | - | - | - |
| 16 | 住所 町域 | `home_address_town` | - | 文字列 | 255 | 制限なし | - | **手動入力モード（`home_is_address_selected_manually=1`）では使用しない（nil）** |
| 17 | 住所 番地以降 | `home_address_later` | ● | 文字列 | 255 | 制限なし | - | - |

### 3. 就労・勤務先情報

| # | フィールド | DBカラム | 必須 | 入力形式 | 最大文字数 | 文字種 | 制限内容 | 備考 |
|---|-----------|---------|-----|---------|----------|--------|---------|------|
| 18 | 就労状況 | `employment_status` | ● | ラジオボタン | - | - | 1=働いている, 2=働いていない, 3=今は答えない | tinyint(1) |
| 19 | 勤務先名 | `workplace_name` | △ | 文字列 | 255 | 制限なし | - | **`employment_status=1`の場合のみ必須** |
| 20 | 勤務先電話番号 | `workplace_phone_number` | △ | 文字列 | 255 | 制限なし | - 形式バリデーションなし（`presence: true`のみ）<br>- 産後ケアRPと同じ仕様 | **`employment_status=1`の場合のみ必須**<br>**正規化処理あり**（電話番号と同じ） |
| 21 | 勤務先住所手動入力有無 | `workplace_is_address_selected_manually` | △ | - | - | - | - | **`employment_status=1`の場合のみ使用**<br>tinyint(1), 0=自動, 1=手動 |
| 22 | 勤務先郵便番号 | `workplace_postal_code` | △ | 文字列 | 8 | 半角数字、ハイフン | - 7桁の数字または「000-0000」の形式で入力<br>- DB保存時はハイフン除去 | **`employment_status=1` かつ `workplace_is_address_selected_manually=0` の場合のみ必須**<br>**全角→半角変換処理あり** |
| 23 | 勤務先都道府県コード | `workplace_prefecture_code` | △ | - | - | - | - | **`employment_status=1`の場合のみ必須** |
| 24 | 勤務先市区町村コード | `workplace_master_city_id` | △ | - | - | - | - | **`employment_status=1`の場合のみ必須** |
| 25 | 勤務先住所 町域 | `workplace_address_town` | - | 文字列 | 255 | 制限なし | - | **手動入力モードでは使用しない（nil）** |
| 26 | 勤務先住所 番地以降 | `workplace_address_later` | △ | 文字列 | 255 | 制限なし | - | **`employment_status=1`の場合のみ必須** |

### 4. その他（登録時は使用しない）

| # | フィールド | DBカラム | 必須 | 備考 |
|---|-----------|---------|-----|------|
| 27 | LINEユーザーID | `line_user_id` | - | LINE連携されている場合に設定される |
| 28 | マイナンバーPPID | `mynumber_ppid` | - | マイナンバーカード連携時に設定される |
| 29 | プロフィール画像 | `profile_image_data` | - | 今後実装予定（MinIO使用） |

---

## 正規表現パターン定義

### 1. ひらがなチェック (`VALID_HIRAGANA_REGEX`)
```ruby
VALID_HIRAGANA_REGEX = /\A[ぁ-んー]+\z/
```
- **使用箇所**: `last_kana_name`, `first_kana_name`
- **許可文字**: ひらがな（ぁ-ん）、長音記号（ー）

### 2. 郵便番号チェック (`VALID_POSTAL_CODE_REGEX`)
```ruby
VALID_POSTAL_CODE_REGEX = /\A\d{3}-?\d{4}\z/
```
- **使用箇所**: `home_postal_code`, `workplace_postal_code`
- **許可形式**: `1234567` または `123-4567`
- **保存時処理**: ハイフンを除去して7桁の数字としてDB保存

### 3. 電話番号 (正規表現チェックなし)
- **使用箇所**: `phone_number`, `workplace_phone_number`
- **バリデーション**: `presence: true` のみ（産後ケアRPと同じ仕様）
- **前処理**（SSO-IdPで追加）:
  - 全角数字→半角数字に変換
  - 全角ハイフン・長音記号→半角ハイフンに変換
  - スペース・括弧を削除
- **保存形式**: 数字とハイフン（両方半角のみ）

### 4. メールアドレスチェック (`VALID_EMAIL_REGEX`)
```ruby
VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
```
- **使用箇所**: `email`
- **備考**: RFC違反も許可（病児保育と合わせる）
- **前処理**: 全角英数字・記号→半角に変換（SSO-IdPで追加）

---

## 条件付きバリデーション

### 1. ミドルネーム
```ruby
# has_middle_name = 1 の場合、middle_name は必須
validates :middle_name, presence: true, if: -> { has_middle_name == 1 }
```

### 2. 自宅住所（自動入力モード）
```ruby
# home_is_address_selected_manually = 0 の場合のみ郵便番号必須
validates :home_postal_code,
  presence: true,
  format: { with: VALID_POSTAL_CODE_REGEX },
  if: -> { home_is_address_selected_manually == 0 }
```

### 3. 就労状況と勤務先情報
```ruby
# employment_status = 1（働いている）の場合、勤務先情報必須
validates :workplace_name, presence: true, if: -> { employment_status == 1 }
validates :workplace_phone_number, presence: true, if: -> { employment_status == 1 }
validates :workplace_address_later, presence: true, if: -> { employment_status == 1 }

# 勤務先住所の自動入力モード
validates :workplace_postal_code,
  presence: true,
  format: { with: VALID_POSTAL_CODE_REGEX },
  if: -> { employment_status == 1 && workplace_is_address_selected_manually == 0 }
```

### 4. 性別の自由記述
```ruby
# gender_code = 4（自由記述）の場合、gender_text は必須
validates :gender_text, presence: true, if: -> { gender_code == 4 }
```

---

## 産後ケアRPとの差分

### SSO-IdP特有の項目
1. **性別** (`gender_code`, `gender_text`) - 産後ケアRPにはない
2. **就労状況** (`employment_status`) - 産後ケアRPにはない
3. **勤務先情報** (`workplace_*`) - 産後ケアRPにはない

### 産後ケアRP特有の項目（SSO-IdPでは不要）
1. **里帰り先住所** (`returning_home_*`) - SSO-IdPにはない
2. **緊急連絡先** (`user_emergency_contact_forms`) - SSO-IdPにはない
3. **本人かどうか** (`person_herself`) - SSO-IdPにはない

### 共通項目
- 基本情報（姓名、ふりがな、ミドルネーム）
- 生年月日
- 電話番号
- 自宅住所（郵便番号、都道府県、市区町村、番地以降）
- 手動入力モード対応

### SSO-IdPで強化する点

#### 1. ミドルネームの厳密化
- **産後ケアRP**: `has_middle_name=1`でも`middle_name`は空欄OK（モデルの`before_save`で自動調整）
- **SSO-IdP**: `has_middle_name=1`の場合、`middle_name`は必須（フォームで検証）
  ```ruby
  validates :middle_name,
    presence: { message: 'ミドルネームを入力してください' },
    if: -> { has_middle_name == 1 }
  ```

#### 2. 正規化処理の追加
- **産後ケアRP**: 郵便番号のハイフン除去のみ
- **SSO-IdP**: 以下の正規化処理を追加
  - **電話番号**: 全角→半角、長音記号→ハイフン、スペース・括弧削除
  - **郵便番号**: 全角→半角変換 + ハイフン除去
  - **メールアドレス**: 全角→半角変換

#### 3. 住所の手動入力モード対応
- **産後ケアRP**: `home_is_address_selected_manually`フィールドはあるがバリデーションなし
- **SSO-IdP**: 自動入力モード（`=0`）の場合のみ郵便番号必須、手動入力モード（`=1`）では都道府県・市区町村選択

---

## Form Objectsパターン実装方針

### ディレクトリ構成
```
app/
  forms/
    form.rb                           # 基底クラス
    users/
      profile_form.rb                 # ユーザープロフィールForm
```

### 基底クラス (`app/forms/form.rb`)

産後ケアRPの実装を参考に以下の機能を実装：

```ruby
class Form
  include ActiveModel::Model

  # 共通の正規表現パターン
  VALID_HIRAGANA_REGEX = /\A[ぁ-んー]+\z/
  VALID_POSTAL_CODE_REGEX = /\A\d{3}-?\d{4}\z/
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  # 電話番号は形式チェックなし（産後ケアRPと同じ）

  # over ride ActiveModel::Model.initialize()
  # 文字列の数字を自動的にIntegerに変換
  def initialize(params={})
    params.each do |attr, value|
      if value.is_a?(String) && /^([1-9]\d*|0)$/.match(value) && (not value.match(/(\n)/))
        params[attr] = value.to_i
      end
    end if params

    super(params)
  end

  # モデルからFormオブジェクトを初期化
  def self.initialize_with_model(model)
    instance = self.new

    columns = ActiveRecord::Base.connection.columns(model.class.table_name).map(&:name)
    columns = columns - %w(created_at updated_at deleted_at)
    columns.each do |column|
      method = (column + '=')
      if instance.respond_to?(method)
        instance.send(method, model.send(column))
      end
    end

    instance
  end
end
```

### プロフィールForm (`app/forms/users/profile_form.rb`)

```ruby
class Users::ProfileForm < Form
  attr_accessor :last_name, :first_name, :has_middle_name, :middle_name,
                :last_kana_name, :first_kana_name,
                :birth_date, :gender_code, :gender_text,
                :phone_number,
                :home_is_address_selected_manually,
                :home_postal_code, :home_prefecture_code, :home_master_city_id,
                :home_address_town, :home_address_later,
                :employment_status,
                :workplace_name, :workplace_phone_number,
                :workplace_is_address_selected_manually,
                :workplace_postal_code, :workplace_prefecture_code, :workplace_master_city_id,
                :workplace_address_town, :workplace_address_later

  # 基本情報
  validates :last_name, presence: { message: '姓を入力してください' }
  validates :first_name, presence: { message: '名を入力してください' }
  validates :last_kana_name,
    presence: { message: '姓（かな）を入力してください' },
    format: { with: VALID_HIRAGANA_REGEX, message: '姓（かな）はひらがなで入力してください' }
  validates :first_kana_name,
    presence: { message: '名（かな）を入力してください' },
    format: { with: VALID_HIRAGANA_REGEX, message: '名（かな）はひらがなで入力してください' }

  # ミドルネーム
  validates :middle_name,
    presence: { message: 'ミドルネームを入力してください' },
    if: -> { has_middle_name == 1 }

  # 生年月日
  validates :birth_date, presence: { message: '生年月日を入力してください' }

  # 性別
  validates :gender_code,
    presence: { message: '性別を選択してください' },
    inclusion: { in: [1, 2, 3, 4], message: '性別の選択が不正です' }
  validates :gender_text,
    presence: { message: '性別（自由記述）を入力してください' },
    if: -> { gender_code == 4 }

  # 電話番号（形式チェックなし、産後ケアRPと同じ）
  validates :phone_number,
    presence: { message: '携帯電話を入力してください' }

  # 自宅住所
  validates :home_postal_code,
    presence: { message: '郵便番号を入力してください' },
    format: { with: VALID_POSTAL_CODE_REGEX, message: '郵便番号の形式が不正です' },
    if: -> { home_is_address_selected_manually == 0 }
  validates :home_address_later,
    presence: { message: '番地以降を入力してください' }

  # 就労状況
  validates :employment_status,
    presence: { message: '就労状況を選択してください' },
    inclusion: { in: [1, 2, 3], message: '就労状況の選択が不正です' }

  # 勤務先情報（就労=1の場合のみ）
  validates :workplace_name,
    presence: { message: '勤務先名を入力してください' },
    if: -> { employment_status == 1 }
  validates :workplace_phone_number,
    presence: { message: '勤務先電話番号を入力してください' },
    if: -> { employment_status == 1 }
  validates :workplace_postal_code,
    presence: { message: '勤務先郵便番号を入力してください' },
    format: { with: VALID_POSTAL_CODE_REGEX, message: '勤務先郵便番号の形式が不正です' },
    if: -> { employment_status == 1 && workplace_is_address_selected_manually == 0 }
  validates :workplace_address_later,
    presence: { message: '勤務先番地以降を入力してください' },
    if: -> { employment_status == 1 }

  # Strong Parametersからの初期化
  def self.initialize_from_params(params)
    permitted = params.permit(
      :last_name, :first_name, :has_middle_name, :middle_name,
      :last_kana_name, :first_kana_name,
      :birth_date, :gender_code, :gender_text,
      :phone_number,
      :home_is_address_selected_manually,
      :home_postal_code, :home_prefecture_code, :home_master_city_id,
      :home_address_town, :home_address_later,
      :employment_status,
      :workplace_name, :workplace_phone_number,
      :workplace_is_address_selected_manually,
      :workplace_postal_code, :workplace_prefecture_code, :workplace_master_city_id,
      :workplace_address_town, :workplace_address_later
    )
    self.new(permitted)
  end

  # Userモデルへの変換
  def to_user_attributes
    attributes = {
      email: normalize_email(email),  # メールアドレスの全角→半角変換
      last_name: last_name,
      first_name: first_name,
      has_middle_name: has_middle_name,
      middle_name: middle_name,
      last_kana_name: last_kana_name,
      first_kana_name: first_kana_name,
      birth_date: birth_date,
      gender_code: gender_code,
      gender_text: gender_text,
      phone_number: normalize_phone_number(phone_number),
      home_is_address_selected_manually: home_is_address_selected_manually,
      home_postal_code: normalize_postal_code(home_postal_code),
      home_prefecture_code: home_prefecture_code,
      home_master_city_id: home_master_city_id,
      home_address_town: home_address_town,
      home_address_later: home_address_later,
      employment_status: employment_status,
      workplace_name: workplace_name,
      workplace_phone_number: normalize_phone_number(workplace_phone_number),
      workplace_is_address_selected_manually: workplace_is_address_selected_manually,
      workplace_postal_code: normalize_postal_code(workplace_postal_code),
      workplace_prefecture_code: workplace_prefecture_code,
      workplace_master_city_id: workplace_master_city_id,
      workplace_address_town: workplace_address_town,
      workplace_address_later: workplace_address_later
    }

    # ミドルネームの正規化
    if has_middle_name == 0
      attributes[:middle_name] = nil
    end

    # 手動入力モードの場合、町域はnil
    if home_is_address_selected_manually == 1
      attributes[:home_address_town] = nil
    end
    if workplace_is_address_selected_manually == 1
      attributes[:workplace_address_town] = nil
    end

    attributes
  end

  private

  # 郵便番号の正規化（全角→半角、ハイフン除去）
  def normalize_postal_code(postal_code)
    return nil if postal_code.blank?
    postal_code.to_s.tr('０-９－', '0-9-').gsub('-', '')
  end

  # 電話番号の正規化（数字とハイフンを半角に統一、スペース・括弧を削除）
  def normalize_phone_number(phone_number)
    return nil if phone_number.blank?
    phone_number.to_s
      .tr('０-９－ー', '0-9--')  # 全角数字・全角ハイフン・長音記号→半角
      .gsub(/[\s()（）]/, '')    # スペース・括弧を削除
  end

  # メールアドレスの正規化（全角→半角）
  def normalize_email(email)
    return nil if email.blank?
    email.to_s.tr('０-９ａ-ｚＡ-Ｚ＠．', '0-9a-zA-Z@.')
  end
end
```

### Controllerでの使用方法

```ruby
class Users::Api::SignUp::ProfileController < Users::Api::BaseController
  wrap_parameters false

  def create
    token = params[:token]

    # Form Objectの初期化
    form = Users::ProfileForm.initialize_from_params(params)

    # バリデーション
    if form.invalid?
      return render json: {
        errors: form.errors.messages
      }, status: :unprocessable_content
    end

    # トークン有効性確認
    signup_ticket = SignupTicketService.find_valid_ticket(token)
    unless signup_ticket
      return render json: {
        errors: { token: ['無効なトークンです'] }
      }, status: :unprocessable_content
    end

    # プロフィールをValkeyに保存
    CacheService.save_signup_cache(token, 'profile', form.to_user_attributes)

    # レスポンス返却
    render json: {
      success: true,
      message: 'プロフィール情報を保存しました'
    }
  rescue StandardError => e
    Rails.logger.error "#{self.class.name}.create failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: {
      errors: { base: ['システムエラーが発生しました'] }
    }, status: :internal_server_error
  end
end
```

---

## WEB版とAPI版の差分

### フィールドの使い分け

| フィールド | WEB版 | API版 | 備考 |
|-----------|------|------|------|
| **基本情報** | ✅ すべて | ✅ すべて | 姓名、ふりがな、生年月日、性別、電話番号 |
| **住所情報** | ✅ すべて | ✅ すべて | 自宅住所（郵便番号、都道府県、市区町村、番地以降） |
| **就労情報** | ✅ すべて | ✅ すべて | 就労状況、勤務先名、勤務先住所 |
| **プロフィール画像** | ✅ あり | ❌ なし | WEB版: multipart/form-data<br>API版: 別エンドポイント（`POST /api/v1/users/:id/avatar`）または画像URL指定 |
| **LINEユーザーID** | ❌ なし | ✅ あり | API版でのみ設定（LINE連携RP経由） |
| **マイナンバーPPID** | ❌ なし | ✅ あり | API版でのみ設定（マイナポータル連携RP経由） |

### 画像アップロードの扱い

#### WEB版（ブラウザ）
```
1. POST /api/upload/profile_image
   Content-Type: multipart/form-data
   → MinIOにアップロード → image_id返却

2. POST /users/api/sign_up/profile
   { ..., profile_image_id: "xxx" }
```

#### RP向けAPI
```
1. POST /api/v1/users
   Content-Type: application/json
   {
     "last_name": "佐藤",
     "first_name": "太郎",
     "line_user_id": "U1234567890abcdef"
     // 画像はなし
   }

2. 別途画像アップロード（必要な場合）
   POST /api/v1/users/:id/avatar
   Content-Type: multipart/form-data
```

**理由**:
- ❌ Base64エンコードでJSONに埋め込むのは非効率（データサイズ大、パース遅い）
- ❌ multipart/form-dataはREST APIでは一般的でない
- ✅ 別エンドポイントが一般的
- ✅ または画像URLをパラメータで受け取る（外部ストレージからコピー）

---

## コンテキスト別の実装方針

### Phase 1（現在）: WEB版のみ対応

```ruby
class Users::ProfileForm < Form
  # WEB版で使うフィールドのみ
  attr_accessor :last_name, :first_name, ..., :workplace_address_later

  # line_user_id, mynumber_ppidは含めない
  # profile_imageは別途実装（Phase 2で画像アップロード機能実装時）

  validates :last_name, presence: true
  validates :first_name, presence: true
  # ...
end
```

### Phase 2（RP向けAPI実装時）: コンテキストで分岐

#### 方法1: コンテキストパラメータで制御（推奨）

```ruby
class Users::ProfileForm < Form
  attr_accessor :last_name, :first_name, ...,
                :line_user_id, :mynumber_ppid,
                :context  # :web, :api

  # 基本バリデーション（全コンテキスト共通）
  validates :last_name, presence: true
  validates :first_name, presence: true
  # ...

  # API経由でのみ検証
  validates :line_user_id,
    format: { with: /\A[a-zA-Z0-9_-]+\z/, message: 'LINEユーザーIDの形式が不正です' },
    if: -> { context == :api && line_user_id.present? }

  validates :mynumber_ppid,
    format: { with: /\A[a-zA-Z0-9-]+\z/, message: 'マイナンバーPPIDの形式が不正です' },
    if: -> { context == :api && mynumber_ppid.present? }

  # Strong Parametersで許可フィールドを制御
  def self.initialize_from_params(params, context: :web)
    fields = [:last_name, :first_name, ...]
    fields += [:line_user_id, :mynumber_ppid] if context == :api

    permitted = params.permit(*fields)
    instance = self.new(permitted)
    instance.context = context
    instance
  end
end
```

#### Controllerでの使い方

```ruby
# WEB版
class Users::Api::SignUp::ProfileController
  def create
    form = Users::ProfileForm.initialize_from_params(params, context: :web)
    # ...
  end
end

# RP向けAPI
class Api::V1::UsersController
  def create
    form = Users::ProfileForm.initialize_from_params(params, context: :api)
    # ...
  end
end
```

#### 方法2: 継承で拡張（API専用フィールドが多い場合）

```ruby
# 基本Form（WEB版）
class Users::ProfileForm < Form
  attr_accessor :last_name, :first_name, ...
  # line_user_id, mynumber_ppidは含めない

  validates :last_name, presence: true
  # ...
end

# API専用Form（継承して拡張）
class Api::Users::ProfileForm < Users::ProfileForm
  attr_accessor :line_user_id, :mynumber_ppid

  validates :line_user_id,
    format: { with: /\A[a-zA-Z0-9_-]+\z/ },
    allow_blank: true

  validates :mynumber_ppid,
    format: { with: /\A[a-zA-Z0-9-]+\z/ },
    allow_blank: true
end
```

### バリデーション原則

**フロントエンド（React）は一切信用しない**
- Backendは常に完全なバリデーションを実行
- Frontendのバリデーションは**UX向上のため**のみ
- JavaScriptは改ざん可能、無効化可能
- データバリデーションはBackendで担保

**Backend APIバリデーションは必須**
- データ整合性保証
- 不正なデータがDBに入るのを防ぐ
- RP向けAPIでも同じバリデーションを使用
- すべてのエンドポイントで必ず実行

**セキュリティの2つのレイヤー**
1. **認証・認可（Controller層）**: JWT/APIキー/セッションチェック、アクセス権限
2. **データバリデーション（Form Objects層）**: 入力値の形式・整合性、XSS/SQLインジェクション対策

Form Objectsは**データバリデーション**のみを担当し、認証・認可はController層で実装する。

---

## メリット

### 1. コードの重複排除
- Users版、SSO版、会員情報変更、RP向けAPIで同じバリデーションロジックを共有
- 現在約200行 × 2ファイル = 400行 → 150行程度に削減

### 2. 保守性向上
- バリデーション変更時、1ファイルのみ修正すればよい
- 宣言的で可読性が高い

### 3. テスト容易性
- Formオブジェクト単体でのテストが可能
- Controllerのテストがシンプルになる

### 4. React化への準備
- バックエンドのバリデーションロジックはそのまま活用
- フロントエンド（React）側で同じバリデーションルールを実装すればリアルタイムバリデーションが可能
- Backendは必ず実行される（Frontendは補助）

### 5. API共通基盤としての活用
- WEB版、RP向けAPIで共通のバリデーションロジック
- コンテキストまたは継承で柔軟に拡張可能
- **データバリデーションを一元的に管理**（認証・認可はController層で別途実装）

---

## 次のステップ

1. **Form Objectsの実装**
   - `app/forms/form.rb` 作成
   - `app/forms/users/profile_form.rb` 作成

2. **Controllerの移行**
   - Users版のProfileControllerを移行
   - SSO版のProfileControllerを移行

3. **テストの作成**
   - `spec/forms/users/profile_form_spec.rb`

4. **フロントエンドバリデーション**
   - React化時に同じルールを実装

---

## 参考資料

- **産後ケアRP実装**: `/Users/n/Workspace/2049/postnatal-care/app/forms/user/user_form.rb`
- **バリデーション一覧**: `tmp/USER_VALIDATION_REPORT.md`
- **画像メモ**: `tmp/user_validation.png`
- **現在の実装**: `app/controllers/users/api/sign_up/profile_controller.rb`
