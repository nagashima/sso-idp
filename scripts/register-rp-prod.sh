#!/usr/bin/env bash
set -e

# RP一括登録スクリプト（本番環境用）
# appコンテナ内から実行: Hydra OAuth2クライアント登録 + IdP RelyingParty登録を連続実行
#
# 使用方法（ECS Exec経由）:
#   aws ecs execute-command --cluster my-cluster --task <task-id> --container app --interactive --command "/bin/bash"
#   bash-5.1$ /app/scripts/register-rp-prod.sh "RP名" "callback_url" [OPTIONS]
#
# OPTIONS:
#   --first-party              信頼済みクライアント（同意画面スキップ）
#   --cors-origin "domains"    CORS許可オリジン（カンマ区切り）
#   --signin-url "URL"         RPのログインページURL
#   --webhook-url "URL"        ユーザー情報変更通知先URL
#
# 例:
#   /app/scripts/register-rp-prod.sh "本番RP" "https://example.com/auth/sso/callback" \
#     --first-party \
#     --cors-origin "https://idp.example.com,https://example.com" \
#     --signin-url "https://example.com/auth/sso"

RP_NAME="$1"
CALLBACK_URL="$2"
FIRST_PARTY=false
CORS_ORIGINS=""
SIGN_IN_URL=""
WEB_HOOK_URL=""

# 引数チェック
if [ -z "$RP_NAME" ] || [ -z "$CALLBACK_URL" ]; then
    echo "❌ 使用方法: $0 RP名 callback_url [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --first-party              信頼済みクライアント（同意画面スキップ）"
    echo "  --cors-origin \"domains\"    CORS許可オリジン（カンマ区切り）"
    echo "  --signin-url \"URL\"         RPのログインページURL"
    echo "  --webhook-url \"URL\"        ユーザー情報変更通知先URL"
    echo ""
    echo "例:"
    echo "  $0 \"本番RP\" \"https://example.com/auth/sso/callback\" --first-party"
    echo "  $0 \"本番RP\" \"https://example.com/auth/sso/callback\" --first-party --signin-url \"https://example.com/auth/sso\""
    exit 1
fi

# オプション引数パース
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --first-party)
            FIRST_PARTY=true
            shift
            ;;
        --cors-origin)
            CORS_ORIGINS="$2"
            shift 2
            ;;
        --signin-url)
            SIGN_IN_URL="$2"
            shift 2
            ;;
        --webhook-url)
            WEB_HOOK_URL="$2"
            shift 2
            ;;
        *)
            echo "❌ 不明なオプション: $1"
            exit 1
            ;;
    esac
done

# callback_urlからdomainを抽出
DOMAIN=$(echo "$CALLBACK_URL" | sed -E 's|^https?://([^/]+).*|\1|')
CLIENT_NAME=$(echo "$CALLBACK_URL" | sed -E 's|^https?://([^/]+).*|\1|')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 RP一括登録開始（本番環境）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RP名: $RP_NAME"
echo "ドメイン: $DOMAIN"
echo "Callback URL: $CALLBACK_URL"
if [ -n "$SIGN_IN_URL" ]; then
    echo "Sign In URL: $SIGN_IN_URL"
fi
if [ -n "$WEB_HOOK_URL" ]; then
    echo "WebHook URL: $WEB_HOOK_URL"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Hydra OAuth2クライアント登録
echo "📝 Step 1/2: Hydra OAuth2クライアント登録中..."

# Hydra起動確認
until curl -f -s http://hydra:4444/health/ready >/dev/null 2>&1; do
    echo "⏳ Hydra起動待ち..."
    sleep 2
done

# JSON payload構築
JSON_PAYLOAD='{'
JSON_PAYLOAD="$JSON_PAYLOAD\"client_name\":\"$CLIENT_NAME\","
JSON_PAYLOAD="$JSON_PAYLOAD\"redirect_uris\":[\"$CALLBACK_URL\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"grant_types\":[\"authorization_code\",\"refresh_token\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"response_types\":[\"code\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"scope\":\"openid profile email\""

# metadata追加
if [ "$FIRST_PARTY" = true ]; then
    JSON_PAYLOAD="$JSON_PAYLOAD,\"metadata\":{\"first_party\":true}"
fi

# CORS設定追加
if [ -n "$CORS_ORIGINS" ]; then
    JSON_PAYLOAD="$JSON_PAYLOAD,\"allowed_cors_origins\":["
    IFS=',' read -ra DOMAINS <<< "$CORS_ORIGINS"
    FIRST_DOMAIN=true
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        if [ "$FIRST_DOMAIN" = true ]; then
            JSON_PAYLOAD="$JSON_PAYLOAD\"$domain\""
            FIRST_DOMAIN=false
        else
            JSON_PAYLOAD="$JSON_PAYLOAD,\"$domain\""
        fi
    done
    JSON_PAYLOAD="$JSON_PAYLOAD]"
fi

JSON_PAYLOAD="$JSON_PAYLOAD}"

# Hydra Admin API呼び出し
CLIENT_JSON=$(curl -s -X POST http://hydra:4445/admin/clients \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

# JSONパース
CLIENT_ID=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_id":"\([^"]*\)".*/\1/p')
CLIENT_SECRET=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_secret":"\([^"]*\)".*/\1/p')

# エラーチェック
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "❌ Hydra登録失敗: レスポンスのパースに失敗しました"
    echo ""
    echo "レスポンス:"
    echo "$CLIENT_JSON"
    exit 1
fi

echo "✅ Hydra登録完了"
echo "   CLIENT_ID: $CLIENT_ID"
echo ""

# Step 2: IdP RelyingParty登録
echo "📝 Step 2/2: IdP RelyingParty登録中..."

# Rails runnerで登録
RAILS_CODE="
rp = RelyingParty.create!(
  name: '$RP_NAME',
  domain: '$DOMAIN',
  api_key: '$CLIENT_ID',
  api_secret: '$CLIENT_SECRET',
  web_hook_url: $([ -n "$WEB_HOOK_URL" ] && echo "'$WEB_HOOK_URL'" || echo "nil"),
  sign_in_url: $([ -n "$SIGN_IN_URL" ] && echo "'$SIGN_IN_URL'" || echo "nil")
)
puts \"✅ RP登録完了: #{rp.name} (ID: #{rp.id})\"
"

bundle exec rails runner "$RAILS_CODE"

if [ $? -ne 0 ]; then
    echo "❌ IdP RP登録失敗"
    exit 1
fi

# 完了メッセージ
cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 RP一括登録完了！
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RP名: $RP_NAME
ドメイン: $DOMAIN
Callback URL: $CALLBACK_URL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 RP側に送付する情報
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
