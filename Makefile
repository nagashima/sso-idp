.PHONY: up down restart build rebuild exec logs app db mysql ps help

# 引数をキャプチャ
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(ARGS):;@:)

up:
	docker compose up -d

down:
	docker compose down

restart: down up

build:
	docker compose build

rebuild:
	docker compose build --no-cache

# 汎用コマンド
exec:
	docker compose exec -it $(ARGS)

logs:
	docker compose logs $(ARGS)

# よく使うショートカット
app:
	docker compose exec -it app bash

db:
	docker compose exec -it db bash

mysql:
	docker compose exec -it db mysql -u rails idp_development -prails_password

ps:
	docker compose ps

help:
	@echo "使用可能なコマンド:"
	@echo "  make up              - コンテナ起動"
	@echo "  make down            - コンテナ停止"
	@echo "  make restart         - 再起動"
	@echo "  make build           - イメージビルド"
	@echo "  make rebuild         - リビルド（キャッシュなし）"
	@echo "  make exec [ARGS]     - コンテナでコマンド実行（例: make exec app rails console）"
	@echo "  make logs [ARGS]     - ログ表示（例: make logs -f hydra）"
	@echo "  make app             - Appコンテナに入る"
	@echo "  make db              - DBコンテナに入る"
	@echo "  make mysql           - MySQL接続"
	@echo "  make ps              - コンテナ一覧"
