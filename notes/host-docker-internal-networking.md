# localhost化に伴うDockerネットワーキング対応

**作成日**: 2025-10-29
**関連**: Phase 1（idp.localhost → localhost:4443 移行）

---

## 問題の背景

### idp.localhost時代（Phase 0）

```
IdP: https://idp.localhost（ポート443）
RP:  https://localhost:3443
```

**ネットワーク構成**:
- ブラウザ → IdP: `https://idp.localhost`
- RPコンテナ → IdP: `https://idp.localhost`（同じ名前でOK）

**なぜ動いた？**
- `idp.localhost` はホストOSの `/etc/hosts` で `127.0.0.1` に設定
- Dockerコンテナからもホストの `/etc/hosts` 経由で名前解決できた

---

### localhost:4443化（Phase 1）で発生した問題

```
IdP: https://localhost:4443
RP:  https://localhost:3443
```

**問題点**:
```
RPコンテナ内から: curl https://localhost:4443
  ↓
localhost = コンテナ自身を指す（IdPではない！）
  ↓
接続エラー
```

**なぜ？**
- Dockerコンテナ内の `localhost` は**そのコンテナ自身**を指す
- ホストOSの `localhost` とは別物

---

## 解決策: host.docker.internal

### host.docker.internal とは

- **Docker特殊DNS名**（Docker Desktop for Mac/Windows専用）
- **ホストOSの `localhost` のみを解決**する専用の名前
- コンテナから「ホストマシンのローカルホスト」にアクセスするための仕組み

### 対応方法

**RP側の設定**（`.env.local`）:
```bash
# ブラウザ用（ユーザーがアクセスするURL）
HYDRA_PUBLIC_URL=https://localhost:4443

# RPコンテナ→IdP通信用（バックエンドからのAPI呼び出し）
HYDRA_INTERNAL_URL=https://host.docker.internal:4443
```

**IdP側の設定**（`docker-compose.yml`）:
```yaml
https-portal:
  environment:
    DOMAINS: 'localhost, host.docker.internal'
  volumes:
    - ./docker/https-portal/localhost.conf.erb:/var/lib/nginx-conf/localhost.conf.erb:ro
    - ./docker/https-portal/host.docker.internal.conf.erb:/var/lib/nginx-conf/host.docker.internal.conf.erb:ro
```

---

## なぜIdP側で2つのドメイン設定が必要？

### 重要な理解: HTTPリクエストのHostヘッダー

**名前解決はDockerが処理するが、HTTPリクエストのHostヘッダーは書き換わらない**

#### ブラウザからのアクセス
```http
GET /auth/login HTTP/1.1
Host: localhost        ← このヘッダー
```

#### RPコンテナからのアクセス
```http
POST /oauth2/token HTTP/1.1
Host: host.docker.internal  ← このヘッダーが異なる
```

### nginxのserver_name

nginxは **`Host` ヘッダーを見て** どの `server` ブロックで処理するか決定します：

```nginx
# localhost.conf.erb
server {
    server_name localhost;  # Host: localhost に応答
    # ...
}

# host.docker.internal.conf.erb
server {
    server_name host.docker.internal;  # Host: host.docker.internal に応答
    # ...
}
```

**両方ないと**:
- `Host: localhost` → ✅ 受け付ける
- `Host: host.docker.internal` → ❌ 404 Not Found（該当するserverブロックなし）

---

## 通信の流れ（詳細）

### RPコンテナ → IdP への通信

```
1. RPコンテナ内のRubyコード:
   HTTPClient.get('https://host.docker.internal:4443/oauth2/token')

2. DNS解決:
   host.docker.internal → ホストOSのlocalhost (例: 192.168.65.2)
   ※Dockerエンジンが内部で解決

3. TCP接続:
   ホストOSの localhost:4443 に接続
   = IdPのhttps-portalコンテナ（ポート4443を公開中）

4. HTTPリクエスト送信:
   POST /oauth2/token HTTP/1.1
   Host: host.docker.internal  ← このヘッダーはそのまま！

5. IdP側nginx/https-portal:
   server_name host.docker.internal; にマッチ
   → リクエスト処理
```

---

## まとめ

| 項目 | idp.localhost時代 | localhost:4443時代 |
|------|------------------|-------------------|
| ブラウザURL | `https://idp.localhost` | `https://localhost:4443` |
| RPコンテナURL | `https://idp.localhost` | `https://host.docker.internal:4443` |
| IdP設定ドメイン | `idp.localhost` のみ | `localhost`, `host.docker.internal` |
| 理由 | 同じ名前で解決可能 | コンテナ内localhostは別物 |

---

## 技術的な補足

### host.docker.internal の制約

- ✅ Docker Desktop for Mac
- ✅ Docker Desktop for Windows
- ❌ Linux版Dockerでは使えない
  - 代替: `172.17.0.1`（Dockerブリッジネットワークのゲートウェイ）
  - または `--add-host=host.docker.internal:host-gateway` オプション

### 代替案（検討しなかった理由）

1. **Docker内部ネットワークでIdPとRPを同じネットワークに配置**
   - メリット: `host.docker.internal` 不要
   - デメリット: 別リポジトリで管理しているため複雑化

2. **IdPをホストOSで直接起動（Dockerを使わない）**
   - メリット: ネットワーク問題なし
   - デメリット: 開発環境の一貫性が失われる

---

## 参考資料

- [Docker Documentation: Networking features in Docker Desktop for Mac](https://docs.docker.com/desktop/networking/#i-want-to-connect-from-a-container-to-a-service-on-the-host)
- 関連コミット: Phase 1（localhost:4443化）
- 関連ファイル:
  - `docker/https-portal/localhost.conf.erb`
  - `docker/https-portal/host.docker.internal.conf.erb`
  - `docker/https-portal/common-config.conf`
