# OmniAuth実装におけるstateパラメータの問題点と改善策

**作成日**: 2025-11-02
**対象**: RP側開発者
**検証環境**: IdP (sso-idp) + RP (sso-rp)

---

## 📋 目次

1. [問題の概要](#問題の概要)
2. [OmniAuthのデフォルト動作](#omniauthのデフォルト動作)
3. [発見された問題点](#発見された問題点)
4. [Hydraの動作確認結果](#hydraの動作確認結果)
5. [改善策](#改善策)
6. [推奨実装パターン](#推奨実装パターン)

---

## 問題の概要

### 背景

OAuth2/OIDCの`state`パラメータは以下の用途で使用できます：

1. **CSRF対策**（必須）
2. **アプリケーション固有のデータ引き継ぎ**（オプション）
   - 招待コード
   - リダイレクト先URL
   - アプリケーション内部ID

### 課題

**OmniAuthはstateパラメータをCSRF対策専用で使用するため、カスタムデータを含められない。**

---

## OmniAuthのデフォルト動作

### 1. 認可リクエスト時

```ruby
# OmniAuthが自動で実行
state = SecureRandom.hex(16)  # ← ランダム文字列（CSRF用）
session[:omniauth_state] = state

# OAuth2リクエスト
GET /oauth2/auth?
  client_id=xxx
  &redirect_uri=https://rp.example.com/callback
  &state=a1b2c3d4e5f6...  # ← CSRF用ランダム文字列のみ
```

### 2. Callback時

```ruby
# OmniAuthが自動で検証
if params[:state] != session[:omniauth_state]
  raise "CSRF attack detected!"
end

# 検証OK → ユーザー情報取得
auth = request.env['omniauth.auth']
```

### 問題点

**stateがCSRF専用で使われているため、招待コードなどのカスタムデータを含められない。**

---

## 発見された問題点

### 問題1: stateの上書きができない

`setup`フックで`state`を上書きしようとしても、OmniAuthが無視する。

```ruby
# ❌ 動かない例
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :openid_connect, {
    name: :sso,
    setup: lambda { |env|
      # カスタムstateを設定しようとする
      custom_state = {
        inviteCode: "abc123",
        csrf: SecureRandom.hex(16)
      }.to_json

      env['omniauth.strategy'].options[:state] = custom_state
      # → OmniAuthが無視して、独自のランダム文字列を生成してしまう
    }
  }
end
```

**結果**: OmniAuthは独自のCSRF用ランダム文字列を生成し、カスタムstateは反映されない。

---

### 問題2: セッション経由では検証にならない

セッションでカスタムデータを引き回す方法は、Hydra経由での検証にならない。

```ruby
# ⚠️ 検証にならない例
# 送信時（ホーム画面）
session[:invite_code] = params[:invite_code]

# OmniAuthが通常通りCSRF用stateを生成
# state=a1b2c3d4...（招待コードは含まれない）

# Callback時
invite_code = session[:invite_code]
# → RP内部のセッションで引き回しているだけ
# → Hydra経由で往復していない
```

**問題**: これではHydraがstateパラメータを正しく返すかの検証にならない。

---

## Hydraの動作確認結果

### 検証方法

OmniAuthをバイパスして、直接OAuth2リクエストを送信する方法で検証を実施。

#### 検証フロー

```ruby
# 1. ホーム画面でカスタムstateを生成
custom_state = {
  inviteCode: params[:invite_code],  # 招待コード
  csrf: SecureRandom.hex(16)         # CSRF対策
}.to_json

# 2. 直接OAuth2リクエストを送信
oauth2_url = "#{ENV['HYDRA_PUBLIC_URL']}/oauth2/auth?" + {
  client_id: ENV['OAUTH_CLIENT_ID'],
  redirect_uri: "https://localhost:3443/auth/test_state/callback",
  response_type: "code",
  scope: "openid profile email",
  state: custom_state  # ← カスタムstate
}.to_query

# 3. Callback時にstateを取得
def test_state_callback
  returned_state = params[:state]
  state_data = JSON.parse(returned_state)
  invite_code = state_data['inviteCode']

  flash[:notice] = "Invite code: #{invite_code}"
  redirect_to root_path
end
```

### 検証結果 ✅

**Hydraはstateパラメータを正しく保持して返すことを確認。**

#### 送信したstate
```json
{
  "inviteCode": "abc123",
  "csrf": "92ca6e0faebf1fe3239a0fee5c35999b"
}
```

#### Callbackで返ってきたstate
```json
{
  "inviteCode": "abc123",
  "csrf": "92ca6e0faebf1fe3239a0fee5c35999b"
}
```

**完全一致！** Hydra経由で正しく往復することを確認。

---

### Hydra DBでの保存状態

Hydraは`hydra_oauth2_flow`テーブルの`request_url`カラムにstateを含むURLを保存：

```sql
SELECT request_url FROM hydra_oauth2_flow ORDER BY requested_at DESC LIMIT 1;

-- 結果
https://localhost:4443/oauth2/auth?
  client_id=xxx
  &state=%7B%22inviteCode%22%3A%22abc123%22%2C%22csrf%22%3A%22xxx%22%7D
```

URLデコード後：
```
state={"inviteCode":"abc123","csrf":"xxx"}
```

**注意点**:
- stateの内容はDB管理者に見える（平文保存）
- 機密情報をstateに含めないこと

---

## 改善策

### 方法1: OmniAuthバイパス（直接OAuth2実装）

**適用ケース**: テスト・検証用、または本格的なカスタム実装

#### メリット
- stateを完全にコントロールできる
- カスタムデータを自由に含められる
- Hydraのstate機能を直接検証できる

#### デメリット
- OmniAuthの便利機能（トークン交換、ユーザー情報取得等）が使えない
- 自分でOAuth2フロー全体を実装する必要がある

#### 実装例

```ruby
# config/routes.rb
get '/auth/custom/callback', to: 'sessions#custom_callback'

# app/controllers/sessions_controller.rb
def custom_callback
  # 1. stateを検証
  returned_state = params[:state]
  state_data = JSON.parse(returned_state)

  # CSRF検証（セッションと比較）
  unless state_data['csrf'] == session[:oauth_csrf]
    return redirect_to root_path, alert: 'Invalid state'
  end

  # 2. 認可コードでトークン交換
  code = params[:code]
  tokens = exchange_code_for_tokens(code)  # 自分で実装

  # 3. ユーザー情報取得
  user_info = fetch_userinfo(tokens[:access_token])  # 自分で実装

  # 4. カスタムデータ（招待コード）を使用
  invite_code = state_data['inviteCode']
  process_invitation(invite_code, user_info)

  redirect_to profile_path
end

private

def exchange_code_for_tokens(code)
  # POST /oauth2/token を実装
  # ...
end

def fetch_userinfo(access_token)
  # GET /userinfo を実装
  # ...
end
```

---

### 方法2: DB/Cache参照方式（OmniAuth併用）

**適用ケース**: OmniAuthの機能を保ちつつ、カスタムデータを扱いたい場合

#### メリット
- OmniAuthのCSRF保護を壊さない
- OmniAuthの便利機能を引き続き使える
- 実装が比較的簡単

#### デメリット
- Hydraのstate機能を使わない（別の方法でデータを引き継ぐ）
- RP側でDB/Cacheの管理が必要
- 有効期限管理が必要

#### 実装例

```ruby
# app/controllers/home_controller.rb
def index
  if params[:invite_code].present?
    # カスタムデータをCacheに保存
    state_id = SecureRandom.uuid
    Rails.cache.write("oauth_state:#{state_id}", {
      invite_code: params[:invite_code],
      created_at: Time.current
    }, expires_in: 10.minutes)

    # OmniAuthのリダイレクトURIに状態IDを含める
    redirect_to "/auth/sso?state_id=#{state_id}"
  end
end

# app/controllers/sessions_controller.rb
def omniauth_callback
  auth = request.env['omniauth.auth']

  # Cacheから招待コードを取得
  state_id = params[:state_id]
  if state_id.present?
    state_data = Rails.cache.read("oauth_state:#{state_id}")
    if state_data
      invite_code = state_data[:invite_code]
      process_invitation(invite_code, auth)
      Rails.cache.delete("oauth_state:#{state_id}")
    end
  end

  # 通常のログイン処理
  session[:user_info] = auth
  redirect_to profile_path
end
```

**注意**: この方法ではHydraのstateパラメータは使わない（OmniAuthのCSRF用のみ）。

---

### 方法3: OmniAuth Gem拡張

**適用ケース**: 本格的にOmniAuthでカスタムstateを扱いたい場合

#### アプローチ
1. `omniauth-openid-connect` gemをfork
2. stateにカスタムデータを含められるよう改造
3. 独自gemとして公開、またはPR送信

#### 実装イメージ

```ruby
# 拡張版OmniAuth
provider :openid_connect, {
  name: :sso,
  custom_state: lambda { |env|
    request = Rack::Request.new(env)
    {
      inviteCode: request.params[:invite_code],
      csrf: SecureRandom.hex(16)  # CSRF対策も含める
    }
  }
}
```

**メリット**:
- OmniAuthの利便性を保ったまま
- カスタムstateを扱える
- 他のRPでも再利用可能

**デメリット**:
- gem開発・保守のコストが高い
- OmniAuth本体の更新に追従する必要がある

---

## 推奨実装パターン

### パターンA: 検証・テスト用途 → **OmniAuthバイパス**

**ユースケース**:
- Hydraのstate機能を検証したい
- プロトタイプ開発
- OAuth2の仕組みを深く理解したい

**推奨度**: ⭐⭐⭐⭐⭐（検証用）

---

### パターンB: 本番アプリ（簡易） → **DB/Cache参照方式**

**ユースケース**:
- 招待コードなどのカスタムデータを扱いたい
- OmniAuthの便利機能を使い続けたい
- 実装コストを抑えたい

**推奨度**: ⭐⭐⭐⭐（本番用）

**実装のポイント**:
```ruby
# 1. 送信前にCacheに保存
state_id = SecureRandom.uuid
Rails.cache.write("oauth:#{state_id}", custom_data, expires_in: 10.minutes)

# 2. URLパラメータで状態IDを引き継ぐ
redirect_to "/auth/sso?state_id=#{state_id}"

# 3. Callback時にCacheから取得
custom_data = Rails.cache.read("oauth:#{params[:state_id]}")
```

**セキュリティ考慮事項**:
- 有効期限を短く設定（5-10分）
- 使用後は即座に削除
- state_idは推測不可能なランダム文字列

---

### パターンC: 本番アプリ（本格） → **OmniAuth拡張Gem**

**ユースケース**:
- 複数のRPで同じ仕組みを使いたい
- メンテナンス性・再利用性を重視
- 長期運用を見据えている

**推奨度**: ⭐⭐⭐⭐⭐（大規模プロジェクト）

---

## セキュリティ上の注意点

### stateに含めて良いデータ

✅ **OK**:
- 招待コード（公開情報）
- リダイレクト先URL（検証必須）
- アプリケーション内部ID
- CSRF対策トークン

### stateに含めてはいけないデータ

❌ **NG**:
- パスワード
- 個人情報（メールアドレス、電話番号等）
- クレジットカード情報
- セッションID
- 機密性の高いトークン

### stateのDB保存について

Hydraは`hydra_oauth2_flow`テーブルの`request_url`にstateを**平文で保存**します。

```sql
-- Hydra DBでstateが見える例
SELECT request_url FROM hydra_oauth2_flow WHERE login_challenge = 'xxx';

-- 結果（URLデコード後）
state={"inviteCode":"abc123","csrf":"xxx"}
```

**対策**:
- 機密情報をstateに含めない
- 必要に応じて暗号化を検討（ただし複雑化する）
- DB管理者のアクセス権限を適切に管理

---

## サンプルコード集

### 完全な実装例（方法2: DB/Cache参照方式）

#### 1. Homeコントローラー

```ruby
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    redirect_to profile_path if user_signed_in?

    # 招待コード付きアクセスの場合
    if params[:invite_code].present?
      save_oauth_state_and_redirect(params[:invite_code])
    end
  end

  private

  def save_oauth_state_and_redirect(invite_code)
    # 状態IDを生成
    state_id = SecureRandom.uuid

    # Cacheに保存（10分有効）
    Rails.cache.write("oauth_state:#{state_id}", {
      invite_code: invite_code,
      created_at: Time.current,
      ip_address: request.remote_ip
    }, expires_in: 10.minutes)

    # OmniAuthのエントリポイントにリダイレクト（状態ID付き）
    redirect_to "/auth/sso?state_id=#{state_id}"
  end
end
```

#### 2. Sessionsコントローラー

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :authenticate_user!

  def omniauth_callback
    auth = request.env['omniauth.auth']

    # OmniAuthのCSRF検証は自動で行われる

    # カスタムデータ（招待コード）を取得
    state_id = params[:state_id]
    invite_code = retrieve_invite_code_from_cache(state_id)

    # ユーザー情報をセッションに保存
    session[:user_info] = {
      uid: auth.uid,
      email: auth.info.email,
      name: auth.info.name,
      access_token: auth.credentials.token
    }

    # 招待コード処理
    if invite_code.present?
      process_invitation(invite_code, auth)
      redirect_to profile_path, notice: "招待コード「#{invite_code}」でログインしました"
    else
      redirect_to profile_path, notice: 'ログインしました'
    end
  end

  private

  def retrieve_invite_code_from_cache(state_id)
    return nil unless state_id.present?

    state_data = Rails.cache.read("oauth_state:#{state_id}")
    return nil unless state_data

    # 使用後は削除
    Rails.cache.delete("oauth_state:#{state_id}")

    # 有効期限チェック（念のため）
    created_at = state_data[:created_at]
    return nil if created_at < 10.minutes.ago

    state_data[:invite_code]
  end

  def process_invitation(invite_code, auth)
    # 招待コードに応じた処理
    # 例: チームへの追加、特典付与等
    Rails.logger.info "Processing invitation: #{invite_code} for user #{auth.uid}"
  end
end
```

#### 3. Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "home#index"

  # OmniAuth（通常通り）
  get '/auth/:provider/callback', to: 'sessions#omniauth_callback'
  get '/auth/failure', to: 'sessions#auth_failure'
  delete '/logout', to: 'sessions#destroy', as: :logout

  get '/profile', to: 'users#show', as: :profile
end
```

#### 4. View（ホーム画面）

```erb
<!-- app/views/home/index.html.erb -->
<div class="container">
  <h1>SSO Login Demo</h1>

  <!-- 通常のSSOログイン -->
  <%= form_with url: "/auth/sso", method: :post do |f| %>
    <%= f.submit "SSO ログイン", class: "btn btn-primary" %>
  <% end %>

  <hr>

  <!-- 招待コード付きアクセスのテスト -->
  <h3>招待コード付きログイン</h3>
  <p>テスト用URL: <code>/?invite_code=abc123</code></p>

  <% if params[:invite_code].present? %>
    <div class="alert alert-info">
      招待コード: <strong><%= params[:invite_code] %></strong>
      <br>
      SSO ログインボタンをクリックしてください。
    </div>
  <% end %>
</div>
```

---

## トラブルシューティング

### Q1: OmniAuthのstateが上書きできない

**A**: OmniAuthは内部でstateを生成するため、直接上書きはできません。方法2（DB/Cache参照）または方法3（Gem拡張）を使用してください。

---

### Q2: セッションで引き回すとHydra検証にならない？

**A**: その通りです。セッションはRP内部だけで完結するため、Hydraのstate機能を検証できません。検証目的の場合は方法1（OmniAuthバイパス）を使用してください。

---

### Q3: stateに機密情報を含めても良い？

**A**: 推奨しません。Hydra DBに平文で保存されるため、機密情報は含めないでください。必要な場合は：
- 暗号化する（ただし複雑化）
- DB参照方式を使う（stateではなくCacheに保存）

---

### Q4: Cache/DBの有効期限はどのくらいが適切？

**A**: OAuth2フローは通常1-2分で完了するため、**5-10分**が適切です。長すぎるとセキュリティリスクが増加します。

---

## まとめ

### 重要なポイント

1. ✅ **Hydraはstateパラメータを正しく保持して返す**（検証済み）
2. ⚠️ **OmniAuthはstateをCSRF専用で使用する**（カスタムデータ不可）
3. 💡 **改善策は3つある**：
   - OmniAuthバイパス（検証・テスト用）
   - DB/Cache参照（本番・簡易）
   - Gem拡張（本番・本格）

### 推奨アプローチ

| 用途 | 推奨方法 | 理由 |
|------|---------|------|
| **検証・テスト** | OmniAuthバイパス | Hydraの動作を直接確認できる |
| **本番（MVP）** | DB/Cache参照 | OmniAuth併用で実装コスト低 |
| **本番（長期）** | Gem拡張 | 保守性・再利用性が高い |

---

**検証日**: 2025-11-02
**検証者**: Claude Code
**検証環境**: sso-idp + sso-rp + Hydra v2.3.0
