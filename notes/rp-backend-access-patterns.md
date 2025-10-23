# RP側バックエンドアクセスパターン - 2つの提案

## 📋 背景

### 問題: RPコンテナ内から IdP にアクセスできない

```
IdP: https://localhost:4443 で提供

ブラウザ: localhost:4443 → ホストOSのポート4443 → IdP ✅

RPコンテナ内: localhost:4443 → コンテナ自身のポート4443 → 何もない ❌
```

**なぜ問題になるのか？**

OAuth2フローでは、RP側で2種類のアクセスが必要：

1. **ブラウザ経由**（ホストOSの名前解決）
   - Authorization リクエスト（リダイレクト）
   - ユーザーがブラウザで IdP にアクセス

2. **RPバックエンド経由**（コンテナ内の名前解決）
   - Token Exchange（POST）
   - UserInfo 取得（GET）
   - RPサーバーが直接 IdP にHTTPリクエスト

**SSOでは両方のネットワーク経路が必須**

---

## 🔍 2つの提案

### 提案1: host.docker.internal 使用（推奨）⭐

**設定方法**:

```bash
# RP側 .env.local
OAUTH_AUTHORIZATION_URL=https://localhost:4443/oauth2/auth       # ブラウザ用
OAUTH_TOKEN_URL=https://host.docker.internal:4443/oauth2/token   # バックエンド用
OAUTH_USERINFO_URL=https://host.docker.internal:4443/userinfo    # バックエンド用
```

```yaml
# RP側 docker-compose.yml（Linux環境のみ必要）
services:
  rp-app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**動作**:
```
┌─────────────────────────────────────┐
│ ホストOS                             │
│ └─ localhost:4443 → IdP             │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ RPコンテナ                    │   │
│  │                              │   │
│  │ ブラウザリダイレクト:         │   │
│  │   localhost:4443 ────────────┼───→ ホストOS:4443
│  │                              │   │
│  │ バックエンドリクエスト:       │   │
│  │   host.docker.internal:4443 ─┼───→ ホストOS:4443
│  │                              │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘

同じホストOSを媒介
```

**メリット**:
- ✅ **Docker標準機能**（Mac/Windows: Docker Desktop標準、Linux: extra_hosts追加のみ）
- ✅ **リポジトリ完全分離**（IdP/RPが互いのコンテナ名を知る必要なし）
- ✅ **シンプル**（環境変数の変更だけ）
- ✅ **本番環境を再現**（異なるサーバー間通信と同じ構造）
- ✅ **配布しやすい**（RPユーザーが理解しやすい）

**デメリット**:
- Linux環境では `extra_hosts` の追加が必要（1行だけ）

---

### 提案2: Docker Network 共有

**設定方法**:

```bash
# 共有ネットワーク作成
docker network create sso-network
```

```yaml
# IdP側 docker-compose.yml
services:
  caddy:  # または nginx
    networks:
      - default
      - sso-network

networks:
  sso-network:
    external: true
```

```yaml
# RP側 docker-compose.yml
services:
  rp-app:
    networks:
      - default
      - sso-network

networks:
  sso-network:
    external: true
```

```bash
# RP側 .env.local（2種類のURLを使い分け）
OAUTH_AUTHORIZATION_URL=https://localhost:4443/oauth2/auth  # ブラウザ用
OAUTH_TOKEN_URL=https://caddy/oauth2/token                  # バックエンド用（コンテナ名）
OAUTH_USERINFO_URL=https://caddy/userinfo                   # バックエンド用（コンテナ名）
```

**動作**:
```
┌─────────────────────────────────────┐
│ ホストOS                             │
│ └─ localhost:4443 → IdP             │
│                                      │
│  ┌──────────────────────────────┐   │
│  │ RPコンテナ                    │   │
│  │                              │   │
│  │ ブラウザリダイレクト:         │   │
│  │   localhost:4443 ────────────┼───→ ホストOS:4443
│  │                              │   │
│  │ バックエンドリクエスト:       │   │
│  │   caddy ─────────────────────┼───→ IdPコンテナ（直接）
│  │          ↑コンテナ名         │   │   ↑ホストOS経由せず
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘

異なる経路を使用
```

**メリット**:
- ✅ **コンテナ間直接通信**（若干高速）
- ✅ **SSL証明書検証回避可能**（内部通信でHTTP使用も可）

**デメリット**:
- ❌ **外部ネットワーク作成が必要**（セットアップ手順増加）
- ❌ **リポジトリ結合**（RPがIdPのコンテナ名を知る必要がある）
- ❌ **2種類のURL管理**（ブラウザ用とバックエンド用で異なる）
- ❌ **配布時の説明が複雑**（共有ネットワークの概念が必要）
- ❌ **本番環境と異なる構成**（本番では別サーバー間通信）

---

## 📊 比較表

| 項目 | host.docker.internal | Docker Network共有 |
|-----|---------------------|-------------------|
| **セットアップ** | シンプル | 外部ネットワーク作成必要 |
| **IdP/RP結合度** | 疎結合（完全独立） | 結合（コンテナ名依存） |
| **URL管理** | 統一（ポート違いのみ） | 2種類（localhost/コンテナ名） |
| **Docker標準** | ✅ 標準機能 | ⚠️ 追加手順 |
| **配布しやすさ** | ✅ 理解しやすい | ⚠️ 説明が複雑 |
| **本番環境再現** | ✅ 同じ構造 | ❌ 異なる構造 |
| **Linux対応** | extra_hosts追加（1行） | 共有ネットワーク作成 |

---

## 🌟 推奨: host.docker.internal

### 理由

1. **RPへの配布を考えるとシンプル**
   - Docker標準機能（特別な知識不要）
   - セットアップ手順が最小限
   - README.mdの説明がシンプル

2. **リポジトリの疎結合**
   - IdP/RPが完全に独立
   - IdPのコンテナ名変更の影響なし
   - マイクロサービス原則に準拠

3. **本番環境を忠実に再現**
   - 異なるサーバー間の通信と同じ構造
   - ホストOSを「ネットワーク」として媒介
   - ブラウザとバックエンド、両方が同じ経路

4. **RP側の理解が自然**
   ```
   ブラウザ: localhost:4443 → ホストOS経由 → IdP
   バックエンド: host.docker.internal:4443 → ホストOS経由 → IdP

   どちらも「ホストOSを媒介する」という同じ概念
   ```

---

## 💡 host.docker.internal とは？

**Docker特殊ホスト名**: コンテナからホストOSにアクセスするためのDNS名

```bash
# コンテナ内で実行
ping localhost
# → 127.0.0.1 (コンテナ自身)

ping host.docker.internal
# → 192.168.65.2 (ホストOSのIP)
```

**プラットフォーム別サポート**:
- **Mac/Windows**: Docker Desktop標準サポート
- **Linux**: `extra_hosts` で有効化（Docker 20.10+）

---

## 🚀 実装ガイド

### Phase 1移行時のRP側対応

```bash
# RP側 .env.local
# 変更前（idp.localhost時代）
OAUTH_TOKEN_URL=https://idp.localhost/oauth2/token
OAUTH_USERINFO_URL=https://idp.localhost/userinfo

# 変更後（localhost:4443移行）
OAUTH_TOKEN_URL=https://host.docker.internal:4443/oauth2/token
OAUTH_USERINFO_URL=https://host.docker.internal:4443/userinfo
```

```yaml
# RP側 docker-compose.yml（Linux環境用、Mac/Windowsは不要）
services:
  rp-app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**これだけでOK！**

---

## 📝 まとめ

### ポイント

1. **SSOでは2つの名前解決が必要**
   - ブラウザの名前解決（ホストOS）
   - コンテナ内の名前解決

2. **host.docker.internal が推奨される理由**
   - Docker標準機能
   - シンプル
   - 疎結合
   - 本番環境を再現

3. **配布版IdPに最適**
   - RPユーザーにとって理解しやすい
   - セットアップ手順が最小限
   - トラブルシューティングが容易

---

**作成日**: 2025-10-22
**対象**: sso-idp/sso-rp 配布版での RPバックエンドアクセス
**関連**: phased-migration-guide.md
