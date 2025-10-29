# https-portal 移行ガイド

**作成日**: 2025-10-29
**対象**: Phase 2（nginx → https-portal 移行）

---

## 概要

nginx（手動SSL証明書管理）から https-portal（自動証明書管理）への移行手順とノウハウをまとめたドキュメント。

---

## なぜ https-portal を選んだか

### Phase 2-A 戦略の比較

| 項目 | https-portal | Caddy | Traefik |
|------|-------------|-------|---------|
| nginx互換性 | ✅ nginxベース | ❌ 独自設定 | ❌ 独自設定 |
| 設定移行 | 簡単 | 困難 | 困難 |
| 学習コスト | 低い | 高い | 高い |
| 証明書管理 | 自動 | 自動 | 自動 |

**結論**: nginx設定を最小限の変更で移行できる https-portal を採用。

詳細: `notes/idp-distribution-strategy.md`

---

## 移行手順

### 1. 既存nginx設定の確認

```bash
# 現在の設定を確認
cat docker/nginx/nginx.conf
```

重要なポイント:
- SSL証明書パス
- proxy設定
- locationブロック
- セキュリティヘッダー

### 2. https-portal用設定ファイルの作成

#### ファイル命名規則（重要！）

**✅ 正しい命名**:
```
docker/https-portal/
├── localhost.ssl.conf.erb              # HTTPS設定（カスタム）
├── host.docker.internal.ssl.conf.erb   # HTTPS設定（カスタム）
└── common-config.conf                  # 共通設定
```

**❌ 間違った命名**:
```
docker/https-portal/
├── localhost.conf.erb                  # ← これだと衝突！
└── host.docker.internal.conf.erb       # ← これも衝突！
```

#### 命名の理由

https-portalは以下の順序で設定を処理:

1. **デフォルトテンプレートから自動生成**:
   - `default.ssl.conf.erb` → `<domain>.ssl.conf`（HTTPS）
   - `default.conf.erb` → `<domain>.conf`（HTTPリダイレクト）

2. **カスタムテンプレートがあれば上書き**:
   - `<domain>.ssl.conf.erb` → `<domain>.ssl.conf`（カスタムHTTPS設定）

**`.ssl.conf.erb` にすることで**:
- ✅ カスタムHTTPS設定がデフォルトを上書き
- ✅ HTTPリダイレクト設定は自動生成される
- ✅ 衝突なし、警告なし

### 3. カスタム設定ファイルの作成

#### localhost.ssl.conf.erb

```nginx
# HTTPS設定 - localhost
server {
    listen 443 ssl;
    http2 on;
    server_name localhost;

    # https-portalが自動生成する証明書を使用
    ssl_certificate <%= domain.chained_cert_path %>;
    ssl_certificate_key <%= domain.key_path %>;

    # 共通設定をinclude
    include /var/lib/nginx-conf/common-config.conf;
}
```

#### ERB変数

https-portalで利用可能なERB変数:

| 変数 | 説明 |
|------|------|
| `<%= domain.chained_cert_path %>` | 証明書パス（自動生成） |
| `<%= domain.key_path %>` | 秘密鍵パス（自動生成） |
| `<%= domain.name %>` | ドメイン名 |
| `<%= domain.port %>` | ポート番号 |

### 4. 共通設定の作成

#### common-config.conf

```nginx
# SSL/TLS設定
ssl_protocols TLSv1.2 TLSv1.3;

# セキュリティヘッダー
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# 共通proxy設定
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-Port $server_port;
proxy_redirect off;
proxy_cookie_flags ~ secure;

# locationブロック
location /auth/ {
    proxy_pass http://web:3000;
}
# ... その他のlocation
```

**ポイント**:
- SSL証明書設定（ERB変数使用）以外は全て共通化可能
- 複数ドメインで同じ設定を使い回せる

### 5. docker-compose.yml の設定

```yaml
https-portal:
  image: steveltn/https-portal:1
  ports:
    - "8080:80"   # HTTP→HTTPS リダイレクト
    - "4443:443"  # HTTPS
  volumes:
    - ./docker/https-portal/localhost.ssl.conf.erb:/var/lib/nginx-conf/localhost.ssl.conf.erb:ro
    - ./docker/https-portal/host.docker.internal.ssl.conf.erb:/var/lib/nginx-conf/host.docker.internal.ssl.conf.erb:ro
    - ./docker/https-portal/common-config.conf:/var/lib/nginx-conf/common-config.conf:ro
  environment:
    STAGE: 'local'  # 自己署名証明書を自動生成
    DOMAINS: 'localhost, host.docker.internal'
  depends_on:
    - web
    - hydra
```

**重要な環境変数**:

| 変数 | 値 | 説明 |
|------|-----|------|
| `STAGE` | `local` | 自己署名証明書を生成 |
| `STAGE` | `staging` | Let's Encrypt Staging環境 |
| `STAGE` | `production` | Let's Encrypt Production環境 |
| `DOMAINS` | `'domain1, domain2'` | 対応ドメインリスト |

### 6. 動作確認

```bash
# コンテナ起動
docker-compose up -d

# ログ確認（警告がないこと）
docker-compose logs https-portal | grep -E "(warn|error)"

# HTTPS接続確認
curl -k -I https://localhost:4443/

# RP連携テスト
# ブラウザで https://localhost:3443/ にアクセスしてSSOログイン
```

---

## トラブルシューティング

### nginx警告: "conflicting server name"

**症状**:
```
nginx: [warn] conflicting server name "localhost" on 0.0.0.0:443, ignored
```

**原因**:
- カスタム設定ファイル名が間違っている（`.conf.erb` を使用）
- https-portal自動生成設定とカスタム設定が衝突

**解決方法**:
```bash
# ファイル名を .ssl.conf.erb にリネーム
mv docker/https-portal/localhost.conf.erb docker/https-portal/localhost.ssl.conf.erb

# docker-compose.yml も更新
# volumes の記述を .ssl.conf.erb に変更

# 再起動
docker-compose down && docker-compose up -d
```

### 404 Not Found（RP連携時）

**症状**:
- ブラウザからのアクセスは成功
- RPコンテナからのアクセスが 404

**原因**:
- `host.docker.internal` 用の設定が不足

**解決方法**:
```bash
# host.docker.internal 用の設定ファイルを追加
cp docker/https-portal/localhost.ssl.conf.erb \
   docker/https-portal/host.docker.internal.ssl.conf.erb

# server_name を変更
# server_name localhost; → server_name host.docker.internal;

# docker-compose.yml の DOMAINS に追加
DOMAINS: 'localhost, host.docker.internal'
```

詳細: `notes/host-docker-internal-networking.md`

### ERB変数のエラー

**症状**:
```
nginx: [emerg] invalid number of arguments in "ssl_certificate"
```

**原因**:
- ERB変数名が間違っている

**正しいERB変数**:
```nginx
# ✅ 正しい
ssl_certificate <%= domain.chained_cert_path %>;
ssl_certificate_key <%= domain.key_path %>;

# ❌ 間違い
ssl_certificate <%= @ssl_certificate_path %>;
ssl_certificate <%= ssl_certificate_path %>;
```

---

## https-portalの内部構造

### ファイル配置

#### ERBテンプレート（処理前）

```
/var/lib/nginx-conf/
├── default.conf.erb                      # デフォルトHTTPテンプレート
├── default.ssl.conf.erb                  # デフォルトSSLテンプレート
├── localhost.ssl.conf.erb                # カスタムSSLテンプレート（マウント）
├── host.docker.internal.ssl.conf.erb     # カスタムSSLテンプレート（マウント）
├── common-config.conf                    # 共通設定（マウント）
└── nginx.conf.erb                        # メインnginx設定
```

#### 生成されたnginx設定（処理後）

```
/etc/nginx/conf.d/
├── localhost.conf             # HTTPリダイレクト（自動生成）
├── localhost.ssl.conf         # HTTPS（カスタム設定）
├── host.docker.internal.conf  # HTTPリダイレクト（自動生成）
└── host.docker.internal.ssl.conf  # HTTPS（カスタム設定）
```

### 処理フロー

```
1. DOMAINS 環境変数を読み取り
   ↓
2. 各ドメインに対して:
   a. カスタムテンプレート（<domain>.ssl.conf.erb）があれば使用
   b. なければデフォルトテンプレート（default.ssl.conf.erb）を使用
   ↓
3. ERB処理（変数展開）
   ↓
4. /etc/nginx/conf.d/ に配置
   ↓
5. nginx reload
```

### 証明書の自動生成

**STAGE: 'local'** の場合:

```
/var/lib/https-portal/
├── localhost/
│   └── local/
│       ├── chained.crt     # 証明書
│       └── domain.key      # 秘密鍵
├── host.docker.internal/
│   └── local/
│       ├── chained.crt
│       └── domain.key
└── dhparam.pem             # DH parameters（共有）
```

**証明書の有効期限**: 90日（自己署名）

---

## ベストプラクティス

### 1. 設定の共通化

**推奨構成**:
```
docker/https-portal/
├── common-config.conf              # 全ての共通設定
├── localhost.ssl.conf.erb          # ドメイン固有: server_name + 証明書のみ
└── host.docker.internal.ssl.conf.erb  # ドメイン固有: server_name + 証明書のみ
```

**メリット**:
- 設定変更が1箇所で済む
- 各ドメイン設定ファイルが最小限（13行程度）
- 保守性が高い

### 2. ファイル命名規則を守る

**必ず `.ssl.conf.erb` を使う**:
- ✅ `<domain>.ssl.conf.erb` - カスタムHTTPS設定
- ❌ `<domain>.conf.erb` - 衝突の原因

### 3. ERB変数を活用

証明書パスは**必ずERB変数**を使用:
```nginx
# ✅ 推奨: ERB変数（自動生成パスに対応）
ssl_certificate <%= domain.chained_cert_path %>;

# ❌ 非推奨: ハードコード（パスが変わると動かない）
ssl_certificate /var/lib/https-portal/localhost/local/chained.crt;
```

### 4. 動作確認を段階的に

```bash
# 1. ログ確認
docker-compose logs https-portal | grep -E "(warn|error)"

# 2. HTTPS接続確認
curl -k -I https://localhost:4443/

# 3. 各エンドポイント確認
curl -k https://localhost:4443/health/ready
curl -k https://localhost:4443/oauth2/token

# 4. RP連携テスト
# ブラウザでSSOログイン
```

---

## よくある質問

### Q1: Let's Encryptの本番証明書を使いたい

**A**: `STAGE: 'production'` に変更し、公開されたドメインを使用:

```yaml
environment:
  STAGE: 'production'
  DOMAINS: 'idp.example.com'
```

**注意**:
- `localhost` や `host.docker.internal` では使えない
- DNS設定が必要
- Rate Limitに注意

### Q2: 複数のドメインで異なる設定を使いたい

**A**: ドメインごとに `.ssl.conf.erb` を作成し、`include` で共通部分と個別部分を分離:

```nginx
# domain1.ssl.conf.erb
server {
    server_name domain1.example.com;
    # ...
    include /var/lib/nginx-conf/common-config.conf;
    include /var/lib/nginx-conf/domain1-specific.conf;
}
```

### Q3: 環境変数で設定を注入できる？

**A**: 部分的に可能だが、証明書設定（ERB変数）は不可:

```yaml
environment:
  CUSTOM_NGINX_SERVER_CONFIG_BLOCK: |
    add_header X-Custom-Header "value" always;
```

ただし、カスタムファイル方式の方が柔軟性が高い。

### Q4: nginxの高度な機能は使える？

**A**: 使える。https-portalは**nginx 1.x ベース**なので、通常のnginx設定がそのまま使用可能:

- rate limiting
- IP制限
- basic認証
- upstream設定
- など

---

## 参考資料

### 公式ドキュメント

- [https-portal GitHub](https://github.com/SteveLTN/https-portal)
- [nginx Documentation](https://nginx.org/en/docs/)

### 関連ドキュメント（このリポジトリ）

- `notes/host-docker-internal-networking.md` - Docker特殊DNS名の解説
- `notes/idp-distribution-strategy.md` - https-portal選択の理由
- `notes/nginx-configuration.md` - nginx設定の詳細
- `notes/migration-guide.md` - Phase 1（localhost化）の手順

### コミット履歴

Phase 2関連コミット:
- `0ea161d` - https-portal基本動作版
- `9db34e5` - 複数ドメイン対応
- `2e62b9f` - 設定重複解消
- `14c7d46` - 設定最適化
- `42c6fdc` - nginx警告解決

---

## まとめ

### 移行の成果

- ✅ 証明書の自動管理
- ✅ 設定の簡素化（66行 → 13行/ドメイン）
- ✅ nginx警告の完全解消
- ✅ RP連携成功

### 重要なポイント

1. **ファイル名は `.ssl.conf.erb`** - 衝突を避ける
2. **ERB変数を使う** - 証明書パスの自動対応
3. **共通設定を活用** - 保守性の向上
4. **段階的に確認** - トラブル早期発見

---

**作成日**: 2025-10-29
**更新日**: 2025-10-29
**ブランチ**: `feature/https-portal`
