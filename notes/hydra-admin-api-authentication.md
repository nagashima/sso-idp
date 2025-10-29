# Hydra Admin API 認証について

**Date**: 2025-10-27

## 結論

**Hydra Admin API (4445) は内部ネットワークからのアクセス時に認証不要**

## 背景

`user_info_controller.rb` で Hydra Introspection API を呼び出す際に、以下のコードがあった：

```ruby
request.basic_auth(ENV['OAUTH_CLIENT_ID'], ENV['OAUTH_CLIENT_SECRET'])
```

しかし、これらの環境変数は `.env` に定義されておらず（nil）、実際には不要だった。

## 調査結果

### Hydra の2つのAPI

| API | ポート | 用途 | 認証 |
|-----|--------|------|------|
| **Public API** | 4444 | OAuth2フロー（外部アクセス） | 必要（context依存） |
| **Admin API** | 4445 | クライアント管理、Introspection等 | **不要（内部のみ）** |

### Introspection API の呼び出し方

#### 現在の実装（IdP → Hydra Admin API）

```ruby
# app/controllers/api/v1/user_info_controller.rb
uri = URI("#{ENV['HYDRA_ADMIN_URL']}/admin/oauth2/introspect")  # 4445
request.set_form_data({ token: token })
# basic_auth 不要！
```

**認証方法**:
- ユーザー特定: `token` パラメータ（access_token）
- クライアント認証: 不要（内部ネットワーク）

#### もし Public API 経由で呼ぶ場合（参考）

```ruby
# 例: 外部RPが直接呼ぶ場合
uri = URI("https://idp.example.com/oauth2/introspect")  # 4444
request.set_form_data({ token: token })
request.basic_auth(client_id, client_secret)  # 必要！
```

## 2つの認証キーの役割

### 1. access_token（必須）

**役割**: ユーザーを特定する

```ruby
request.set_form_data({ token: token })
```

- ログイン時に Hydra が発行
- トークンに紐づくユーザー情報を取得するための鍵
- Hydra Introspection のレスポンス例：

```json
{
  "active": true,
  "sub": "123",           // ← ユーザーID
  "client_id": "rp_abc",
  "scope": "openid profile email",
  "exp": 1234567890
}
```

### 2. client_id/client_secret（不要 - 内部アクセスの場合）

**役割**: APIを呼び出すクライアント（RP）を認証する

```ruby
request.basic_auth(client_id, client_secret)
```

- RP登録時に Hydra が発行
- 「このAPIを呼んでいるのは正当なRPか？」を確認
- **IdPは内部ネットワークから呼ぶため不要**

## IdP の Hydra への登録状況

| システム | Hydraへの登録 | 用途 |
|---------|-------------|------|
| RP1, RP2, ... | ✅ 登録あり | OAuth2クライアントとして |
| **IdP (Rails)** | ❌ 登録なし | 内部管理サーバーとして動作 |

IdP は Hydra の OAuth2 クライアントではなく、管理者として Admin API を利用する。

## セキュリティ

### 本番環境での注意点

1. **Admin API (4445) を外部に公開しない**
   - nginx 等で外部からのアクセスをブロック
   - Docker内部ネットワークのみに制限

2. **Public API (4444) は外部公開OK**
   - HTTPS必須
   - 適切な認証が実装されている

## 関連ファイル

- `app/controllers/api/v1/user_info_controller.rb` - Introspection API 呼び出し
- `docker/nginx/nginx.conf` - Admin API の外部公開設定
- `docker-compose.yml` - Hydra のポート設定

## 変更履歴

| Date | Change |
|------|--------|
| 2025-10-27 | user_info_controller.rb から basic_auth 削除（動作確認済み） |

---

**参考**: [ORY Hydra Documentation - Token Introspection](https://www.ory.sh/docs/hydra/guides/token-introspection)
