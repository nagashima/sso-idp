# Vite HMR (Hot Module Replacement) セットアップガイド

## 概要

Rails + Vite + React環境でのHMR動作に必要な設定をまとめたドキュメント。

## 🎯 前提条件

- Rails 8.0 + Vite 7.x + React 19.x
- `@vitejs/plugin-react-swc` 使用
- nginx経由でのHTTPSアクセス対応

---

## ✅ 必須設定：preambleのimport

### 問題

Rails等のバックエンドフレームワーク統合では、Viteの`transformIndexHtml` APIが使われないため、React Fast Refreshのpreambleが自動注入されない。

### エラー例

```
Uncaught Error: @vitejs/plugin-react-swc can't detect preamble. Something is wrong.
```

### 解決方法

**全てのReactエントリーポイント**の**先頭行**に以下をimport：

```tsx
import '@vitejs/plugin-react-swc/preamble';
import React from 'react';
import { createRoot } from 'react-dom/client';
// ... 以降のコード
```

**適用箇所例**：
- `app/frontend/entrypoints/LoginForm.tsx`
- `app/frontend/entrypoints/UserRegistration.tsx`
- `app/frontend/entrypoints/test-react.tsx`

**重要**：必ず最初の行に配置すること。

---

## 🔧 リバースプロキシ経由（HTTPS）でのHMR対応

### 1-A. https-portal設定（WebSocketプロキシ）**← 現在使用中**

**ファイル**: `docker/https-portal/common-config.conf`

```nginx
# Vite dev server - HMR WebSocket用 (port 3036)
location /vite-dev/ {
    proxy_pass http://app:3036;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

**https-portal固有の設定**：
- `docker/https-portal/localhost.ssl.conf.erb` で `common-config.conf` をinclude
- https-portalが自動的に証明書を生成・管理

---

### 1-B. 素のnginx設定（参考：nginx直接使用の場合）

**ファイル**: `docker/nginx/nginx.conf`

```nginx
# Vite dev server - HMR WebSocket用 (port 3036)
location /vite-dev/ {
    proxy_pass http://web:3036;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

**ポイント**：
- locationブロックで`proxy_set_header`を書くと、親（server）レベルの設定が無効化される
- WebSocket用のheaderと通常のproxy headerを**全て**記述する必要がある

---

### 2. Vite設定（HMR WebSocket接続先）

**ファイル**: `vite.config.ts`

```typescript
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import ReactSwc from '@vitejs/plugin-react-swc'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    ReactSwc()
  ],
  server: {
    hmr: process.env.VITE_HMR_PROTOCOL ? {
      protocol: process.env.VITE_HMR_PROTOCOL as 'ws' | 'wss',
      host: process.env.VITE_HMR_HOST,
      clientPort: parseInt(process.env.VITE_HMR_PORT || '443')
    } : true
  }
})
```

**ポイント**：
- 環境変数で動的に設定（環境依存のハードコード回避）
- `process.env.VITE_HMR_PROTOCOL`がない場合は`true`（デフォルト動作）

---

### 3. 環境変数設定

**ファイル**: `.env`

```bash
# Vite HMR WebSocket Configuration (for HTTPS access)
VITE_HMR_PROTOCOL=wss
VITE_HMR_HOST=localhost
VITE_HMR_PORT=4443
```

**プロジェクト別の例**：

```bash
# idpプロジェクト（idp.localhost:443）の場合
VITE_HMR_PROTOCOL=wss
VITE_HMR_HOST=idp.localhost
VITE_HMR_PORT=443

# sso-idpプロジェクト（localhost:4443）の場合
VITE_HMR_PROTOCOL=wss
VITE_HMR_HOST=localhost
VITE_HMR_PORT=4443
```

**docker-compose.yml**: 環境変数は自動的に`.env`から読み込まれる

---

### 4. CSP（Content Security Policy）設定

**ファイル**: `app/controllers/application_controller.rb`

```ruby
# Vite開発サーバー用WebSocket接続許可（開発環境のみ）
csp_policy = "default-src 'self'; script-src 'self' 'unsafe-inline' cdn.tailwindcss.com; style-src 'self' 'unsafe-inline' cdn.tailwindcss.com"
if Rails.env.development?
  vite_host = ENV['VITE_HMR_HOST'] || 'localhost'
  vite_port = ENV['VITE_RUBY_PORT'] || '3036'
  csp_policy += "; connect-src 'self' wss://#{vite_host} wss://#{vite_host}:#{vite_port} ws://localhost:#{vite_port} ws://localhost:3037"
end

response.headers['Content-Security-Policy'] = csp_policy
```

**ポイント**：
- WebSocket接続を許可するため`connect-src`に追加
- 環境変数で動的に設定（プロジェクトごとに柔軟に対応）

---

## 🧪 動作確認

### 1. localhost:3000（直接アクセス）

```
http://localhost:3000/test-react
```

- Reactコンポーネントを編集
- 保存
- ブラウザがリロードせずに即座に反映されるか確認

### 2. https-portal経由（HTTPS）

```
# sso-idpプロジェクトの場合
https://localhost:4443/test-react

# idpプロジェクトの場合
https://idp.localhost/test-react
```

- 同様にHMRが動作するか確認
- ブラウザコンソールにWebSocketエラーが出ないか確認
- WebSocket接続先が正しいか確認（例：`wss://localhost:4443/vite-dev/`）

---

## 📋 トラブルシューティング

### preambleエラーが出る

```
@vitejs/plugin-react-swc can't detect preamble
```

→ **全てのエントリーポイント**に`import '@vitejs/plugin-react-swc/preamble';`を追加

### リバースプロキシ経由でWebSocket接続失敗

```
WebSocket connection to 'wss://localhost:4443/vite-dev/' failed
```

→ https-portalの場合: `common-config.conf`に`location /vite-dev/`のWebSocketプロキシ設定を追加
→ nginx直接使用の場合: `nginx.conf`に`location /vite-dev/`のWebSocketプロキシ設定を追加

### CSPエラー

```
Refused to connect to 'wss://localhost:4443/vite-dev/' because it violates CSP
```

→ `application_controller.rb`のCSP設定に`connect-src`で`wss://`接続先を追加

---

## 🔗 参考資料

- [Vite Backend Integration](https://vitejs.dev/guide/backend-integration.html)
- [@vitejs/plugin-react-swc Documentation](https://github.com/vitejs/vite-plugin-react-swc)
- [nginx WebSocket Proxying](http://nginx.org/en/docs/http/websocket.html)

---

**作成日**: 2025-10-27
**最終更新**: 2025-11-05（https-portal対応追記）
**対象環境**: Rails 8.0.3 + Vite 7.1.12 + React 19.2.0
