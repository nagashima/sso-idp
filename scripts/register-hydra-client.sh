#!/usr/bin/env bash
set -e

# シンプルなOAuth2クライアント登録スクリプト
# 使用方法: ./register-client.sh "https://localhost:3443/callback" [--first-party] [--cors-origin "domain1,domain2"]
# ex) ./register-client.sh "https://localhost:3443/auth/sso/callback" --first-party --cors-origin "https://localhost:4443,https://localhost:3443"

REDIRECT_URI="$1"
FIRST_PARTY=false
CORS_ORIGINS=""

# 引数パース
shift
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
        *)
            echo "❌ 不明なオプション: $1"
            exit 1
            ;;
    esac
done

# バリデーション
if [ -z "$REDIRECT_URI" ]; then
    echo "❌ 使用方法: $0 REDIRECT_URI [--first-party] [--cors-origin \"domain1,domain2\"]"
    echo ""
    echo "例:"
    echo "  $0 \"http://localhost:3001/auth/callback\""
    echo "  $0 \"http://localhost:3001/auth/callback\" --first-party"
    echo "  $0 \"https://localhost:3443/auth/sso/callback\" --first-party --cors-origin \"https://localhost:4443,https://localhost:3443\""
    exit 1
fi

# Hydra起動確認
echo "🔍 Hydra確認中..."
until docker-compose exec hydra wget -q --spider http://localhost:4444/health/ready 2>/dev/null; do
    echo "⏳ Hydra起動待ち..."
    sleep 2
done

# リダイレクトURIからホスト名を抽出（クライアント名として使用）
CLIENT_NAME=$(echo "$REDIRECT_URI" | sed -E 's|^https?://([^/]+).*|\1|')

# コマンド構築
HYDRA_CMD="docker-compose exec hydra hydra create oauth2-client"
HYDRA_CMD="$HYDRA_CMD --endpoint http://localhost:4445"
HYDRA_CMD="$HYDRA_CMD --format json"
HYDRA_CMD="$HYDRA_CMD --name \"$CLIENT_NAME\""
HYDRA_CMD="$HYDRA_CMD --scope openid --scope profile --scope email"
HYDRA_CMD="$HYDRA_CMD --grant-type authorization_code --grant-type refresh_token"
HYDRA_CMD="$HYDRA_CMD --response-type code"
HYDRA_CMD="$HYDRA_CMD --redirect-uri \"$REDIRECT_URI\""

# metadata追加
if [ "$FIRST_PARTY" = true ]; then
    HYDRA_CMD="$HYDRA_CMD --metadata '{\"first_party\": true}'"
fi

# CORS設定追加
if [ -n "$CORS_ORIGINS" ]; then
    IFS=',' read -ra DOMAINS <<< "$CORS_ORIGINS"
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        HYDRA_CMD="$HYDRA_CMD --allowed-cors-origin \"$domain\""
    done
fi

# 実行
echo "📝 クライアント登録中..."
echo "   Redirect: $REDIRECT_URI"
echo "   First Party: $([ "$FIRST_PARTY" = true ] && echo "Yes" || echo "No")"
if [ -n "$CORS_ORIGINS" ]; then
    echo "   CORS Origins: $CORS_ORIGINS"
fi
echo ""

CLIENT_JSON=$(eval $HYDRA_CMD)

if [ $? -eq 0 ]; then
    # JSONパース（sed使用、jq不要でWindows環境でも動作）
    CLIENT_ID=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_id":"\([^"]*\)".*/\1/p')
    CLIENT_SECRET=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_secret":"\([^"]*\)".*/\1/p')

    # 見やすく整形して出力
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ OAuth2 Client 登録完了
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Client Name: $CLIENT_NAME
Callback URL: $REDIRECT_URI
First Party: $([ "$FIRST_PARTY" = true ] && echo "Yes" || echo "No")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 RP側に送付する情報（コピーしてSlack/メール等で共有）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 RP側の .env.local 設定内容
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OAUTH_CLIENT_ID=$CLIENT_ID
OAUTH_CLIENT_SECRET=$CLIENT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # オプション: ファイルに保存
    mkdir -p tmp
    OUTPUT_FILE="tmp/client-${CLIENT_NAME}.env"
    cat > "$OUTPUT_FILE" << EOF
# OAuth2 Client Credentials for $CLIENT_NAME
# Generated: $(date)
# Callback URL: $REDIRECT_URI

OAUTH_CLIENT_ID=$CLIENT_ID
OAUTH_CLIENT_SECRET=$CLIENT_SECRET
EOF

    echo "💾 設定ファイルを保存しました: $OUTPUT_FILE"
    echo ""
else
    echo "❌ 登録失敗"
    exit 1
fi
