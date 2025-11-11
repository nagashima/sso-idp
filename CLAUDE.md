# CLAUDE.md

**重要**:
- 思考は英語で行う（効率的な推論のため）
- 回答は常に日本語で行う
- Gitへのコミットや、メモ・ドキュメントへのClaude Codeの署名は不要
- 常に懸念点は確認、問題点があれば情報をまず提供。曖昧なまま進めない

## 🎯 プロジェクト概要

ORY Hydraを活用したSSO（Single Sign-On）認証システムのIdentity Provider（IdP）を、最新のRails 8.0環境で構築。外部のRelying Party（RP）から独立したIdP専用アプリケーションとして開発し、Docker Composeによる開発環境で実装・テストを行う。

### 技術スタック
- **Backend**: Rails 8.0.3 + Ruby 3.4.7
- **Frontend**: React 19.2.0 + Vite 7.1.3
- **Infrastructure**: Docker + https-portal(nginx) + MySQL 8.0 + Valkey 8.0
- **SSO**: ORY Hydra v2.3.0