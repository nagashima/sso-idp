#!/usr/bin/env bash
set -e

# RP一括登録スクリプト（開発環境用）
# Hydra OAuth2クライアント登録 + IdP RelyingParty登録を連続実行
#
# 使用方法: ./register-rp-dev.sh "RP名" "callback_url" [OPTIONS]
#
# OPTIONS:
#   --first-party              信頼済みクライアント（同意画面スキップ）
#   --cors-origin "domains"    CORS許可オリジン（カンマ区切り）
#   --signin-url "URL"         RPのログインページURL
#   --webhook-url "URL"        ユーザー情報変更通知先URL
#
# 例:
#   ./register-rp-dev.sh "検証用RP" "https://localhost:3443/auth/sso/callback" \
#     --first-party \
#     --cors-origin "https://localhost:4443,https://localhost:3443" \
#     --signin-url "https://localhost:3443/auth/sso"

RP_NAME="$1"
CALLBACK_URL="$2"
FIRST_PARTY_FLAG=""
CORS_ORIGIN_FLAG=""
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
    echo "  $0 \"検証用RP\" \"https://localhost:3443/auth/sso/callback\" --first-party"
    echo "  $0 \"検証用RP\" \"https://localhost:3443/auth/sso/callback\" --first-party --signin-url \"https://localhost:3443/auth/sso\""
    exit 1
fi

# オプション引数パース
shift 2
while [[ $# -gt 0 ]]; do
    case $1 in
        --first-party)
            FIRST_PARTY_FLAG="--first-party"
            shift
            ;;
        --cors-origin)
            CORS_ORIGIN_FLAG="--cors-origin \"$2\""
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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 RP一括登録開始"
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
HYDRA_CMD="./scripts/register-hydra-client.sh \"$CALLBACK_URL\" $FIRST_PARTY_FLAG $CORS_ORIGIN_FLAG"
HYDRA_OUTPUT=$(eval $HYDRA_CMD)

if [ $? -ne 0 ]; then
    echo "❌ Hydra登録失敗"
    exit 1
fi

# CLIENT_IDとCLIENT_SECRETを抽出
CLIENT_ID=$(echo "$HYDRA_OUTPUT" | grep "^CLIENT_ID=" | cut -d'=' -f2)
CLIENT_SECRET=$(echo "$HYDRA_OUTPUT" | grep "^CLIENT_SECRET=" | cut -d'=' -f2)

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "❌ CLIENT_IDまたはCLIENT_SECRETの取得に失敗しました"
    echo "$HYDRA_OUTPUT"
    exit 1
fi

echo "✅ Hydra登録完了"
echo "   CLIENT_ID: $CLIENT_ID"
echo ""

# Step 2: IdP RelyingParty登録
echo "📝 Step 2/2: IdP RelyingParty登録中..."
IDP_CMD="./scripts/register-idp-rp.sh \"$RP_NAME\" \"$DOMAIN\" \"$CLIENT_ID\" \"$CLIENT_SECRET\""

if [ -n "$SIGN_IN_URL" ]; then
    IDP_CMD="$IDP_CMD --signin-url \"$SIGN_IN_URL\""
fi

if [ -n "$WEB_HOOK_URL" ]; then
    IDP_CMD="$IDP_CMD --webhook-url \"$WEB_HOOK_URL\""
fi

eval $IDP_CMD

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
