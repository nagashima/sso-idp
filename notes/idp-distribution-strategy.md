# IdP提供戦略

## 概要

RPプロジェクトで簡単に利用できるIdPを提供するためのアーキテクチャと実装方針。

**主要目標**:
- `docker-compose up` だけで起動
- `/etc/hosts` 設定不要
- 既存RPプロジェクトに影響を与えない

---

## 現在の構成（Phase 1実装済み）

### アクセス方法
- IdP: `https://localhost:4443`
- RP: `https://localhost:3443`（例）

### インフラ
- リバースプロキシ: nginx
- SSL証明書: 自己署名（手動管理、1年ごと再生成）
- ポートマッピング: `4443:443`

### 特徴
- ✅ `/etc/hosts` 設定不要
- ✅ ポート違い = 別オリジン（CORS動作維持）
- ✅ 動作確認済みのnginx設定を活用
- ⚠️ 証明書の手動更新が必要（1年ごと）

---

## アーキテクチャの判断理由

### ドメイン・ポート設定の選択

#### 検討した選択肢

**パターンA: `idp.localhost`（旧構成）**
```
IdP: https://idp.localhost (port 443)
RP:  https://localhost:3443
```

- ✅ 分かりやすいホスト名
- ❌ `/etc/hosts` 設定が必要
- ❌ OS依存の設定手順

**パターンE: `localhost:4443`（採用）**
```
IdP: https://localhost:4443
RP:  https://localhost:3443
```

- ✅ `/etc/hosts` 設定不要
- ✅ `docker-compose up` だけで完結
- ✅ ポート違い = 別オリジン（CORS動作維持）

#### Same-Origin Policyの確認

```
Origin = スキーム + ホスト + ポート

https://localhost:4443 (IdP)
https://localhost:3443 (RP)
→ ポートが異なる = 別オリジン = CORS必要
```

**ポートによる振り分け**:
```
ブラウザ → https://localhost:4443
  ↓
ホストOS (ポート4443)
  ↓
IdP docker-compose → nginx → Rails/Hydra

ブラウザ → https://localhost:3443
  ↓
ホストOS (ポート3443)
  ↓
RP docker-compose → RPアプリ
```

ポート番号でホストOSが振り分けるため、完全に独立したdocker-compose領域として動作。

---

## Phase 2: 証明書自動化（オプション）

### Phase 2の位置づけ

**Phase 1で主要目標は達成済み**。Phase 2は証明書の1年ごとの手動更新を自動化したい場合のみ実施。

- Phase 1: `/etc/hosts` 不要、`docker-compose up` で起動 ✅
- Phase 2: 証明書自動管理（オプション）

### 選択肢比較

#### Phase 2-A: https-portal（推奨）

| 項目 | 内容 |
|-----|------|
| **ベース** | nginx |
| **nginx設定継承** | ✅ ほぼそのまま使える |
| **動作確実性** | ✅ 高い（nginxベース） |
| **証明書自動生成** | `STAGE: local` で自己署名 |
| **検証コスト** | 低い |
| **nginx知識の活用** | ✅ そのまま活かせる |

**推奨理由**:
- 現在のnginx.confをほぼコピーするだけ
- 動作確認済みの設定を継承
- プロキシヘッダー設定を維持しやすい

**設定イメージ**:
```yaml
# docker-compose.yml
https-portal:
  image: steveltn/https-portal:1
  environment:
    STAGE: 'local'  # 自己署名証明書自動生成
    DOMAINS: 'localhost'
  volumes:
    - ./docker/https-portal/localhost.conf.erb:/var/lib/nginx-conf/localhost.conf.erb:ro
```

```nginx
# localhost.conf.erb
server {
    listen 443 ssl http2;
    server_name localhost;

    # https-portalが自動生成
    ssl_certificate <%= @ssl_certificate_path %>;
    ssl_certificate_key <%= @ssl_certificate_key_path %>;

    # 既存のプロキシ設定をそのまま
    proxy_set_header X-Forwarded-Proto https;
    proxy_cookie_flags ~ secure;
    # ...
}
```

---

#### Phase 2-B: Caddy（参考）

| 項目 | 内容 |
|-----|------|
| **ベース** | 独自（Go製） |
| **nginx設定継承** | ❌ 書き換え必要 |
| **動作確実性** | ⚠️ 検証必要 |
| **証明書自動生成** | `local_certs` |
| **検証コスト** | 高い |
| **設定のシンプルさ** | ✅ Caddyfile 20行程度 |

**特徴**:
- 設定がシンプル
- プロキシヘッダー・Cookie設定の検証が必要
- nginx設定の書き換えが必要

**設定イメージ**:
```caddyfile
{
    local_certs  # 自己署名証明書自動生成
}

localhost:4443 {
    reverse_proxy /auth/* web:3000
    reverse_proxy /oauth2/* hydra:4444
    reverse_proxy /health/* hydra:4444
    reverse_proxy /.well-known/* hydra:4444
    reverse_proxy /userinfo hydra:4444
    reverse_proxy /* web:3000

    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    header Set-Cookie {
        +Secure
    }
}
```

---

### Phase 2の選択基準

| 状況 | 推奨 |
|------|------|
| nginx設定を継承したい | https-portal |
| 動作確実性を重視 | https-portal |
| 検証コストを低く抑えたい | https-portal |
| 設定のシンプルさを重視 | Caddy |
| 新しい技術を試したい | Caddy |

**詳細な実装手順**: `migration-guide.md` の Phase 2セクションを参照

---

## 技術的知見

### Same-Site判定とポート番号

**RFC 6265bisの定義**:
```
Same-Site = スキーム + ドメイン
（ポート番号は無関係）
```

**実例**:
```
https://localhost:4443  ─┐
https://localhost:3443  ─┤ Same-Site
https://localhost:8080  ─┘

https://idp.localhost   ─┐
https://rp.localhost    ─┤ Cross-Site
```

**検証結果**:
- `localhost:4443` と `localhost:3443` は **Same-Site**
- ただし、**Origin は異なる**（ポート番号を含む）
- CORS は動作する（Origin判定）
- `SameSite=Strict` Cookieでも送信される

---

### ステートレス運用の利点

**Hydra remember機能**:
```
remember: false（現在の設定）
- Hydraが独自セッションを保持しない
- 毎回IdP側で認証状態を判断
- IdPのJWT Cookieで管理
```

**メリット**:
1. **障害耐性**: Hydra再起動でもユーザーセッション継続
2. **スケーラビリティ**: セッション共有不要、水平スケール容易
3. **運用性**: 状態がIdP側に集約、デバッグしやすい
4. **セキュリティ**: Hydra侵害でもセッション情報が残らない
5. **Cookie問題回避**: クロスドメインCookie設定への依存が少ない

**デメリット**:
- 毎回IdP処理が発生（ただし軽量）

**結論**: ステートレス運用が理想的（特にマイクロサービス環境）

**詳細**: `tmp/hydra-remember-mode-analysis.md` を参照

---

### host.docker.internal の仕組み

**概要**: コンテナから「ホストOSのlocalhost」にアクセスするためのDocker特殊ホスト名

**仕組み**:
```
┌─────────────────────────────────────┐
│ ホストOS                             │
│ └─ localhost:4443 → IdP             │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ RPコンテナ内                  │   │
│  │ localhost = 自分自身          │   │
│  │ host.docker.internal = ホストOS│  │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

**名前解決**:
- Docker内部DNSが解決（`/etc/hosts` は無関係）
- ホストOSの内部IPに変換
- Linux: `extra_hosts: "host.docker.internal:host-gateway"` が必要
- Mac/Windows: Docker Desktopが自動サポート

**用途**:
- RPバックエンド → IdP API通信
- `https://host.docker.internal:4443/oauth2/token`

**詳細**: `rp-backend-access-patterns.md` を参照

---

### nginxプロキシヘッダーの動的化

**Phase 1実装での改善**:

**変更前**（固定値）:
```nginx
proxy_set_header Host $host;              # ポート番号なし
proxy_set_header X-Forwarded-Port 443;    # 固定値
```

**変更後**（動的）:
```nginx
proxy_set_header Host $http_host;         # ポート番号込み
proxy_set_header X-Forwarded-Port $server_port;  # 実際のポート
```

**メリット**:
- ポート番号が変わっても動作
- Railsが正確なURLを生成可能
- デバッグしやすい

---

## RP側の協調設定

### Phase 1での必須変更

**RPコンテナ内から IdP にアクセスするため**:

`.env.local`:
```bash
# ブラウザ用（ユーザーのブラウザがアクセス）
HYDRA_PUBLIC_URL=https://localhost:4443

# バックエンド用（RPコンテナ内からアクセス）
HYDRA_INTERNAL_URL=https://host.docker.internal:4443
IDP_API_INTERNAL_URL=https://host.docker.internal:4443/api/v1
```

`docker-compose.yml`:
```yaml
services:
  rp-app:
    extra_hosts:
      - "host.docker.internal:host-gateway"  # Linux用
```

### Phase 2での変更

**不要** - IdP内部の変更のみ（疎結合）

---

## 参考資料

- **実装手順**: `migration-guide.md`
- **nginx設定詳細**: `nginx-configuration.md`
- **RPアクセスパターン**: `rp-backend-access-patterns.md`
- **Hydra remember機能**: `tmp/hydra-remember-mode-analysis.md`
- **検討履歴**: `idp-distribution-strategy-planning.md`

---

**作成日**: 2025-10-23
**対象環境**: Rails 8.0 + ORY Hydra v2.3.0
