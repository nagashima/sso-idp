# Node.js環境準備
FROM node:22-slim AS node-base
FROM ruby:3.4.7-slim

# 環境変数設定
ENV RAILS_ENV="development" \
    BUNDLE_PATH="/usr/local/bundle" \
    LANG="C.UTF-8" \
    TZ="Asia/Tokyo"

# 必要なネイティブライブラリをインストール
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    default-libmysqlclient-dev \
    libyaml-dev \
    git \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Node.js環境統合
COPY --from=node-base /usr/local/bin/node /usr/local/bin/
COPY --from=node-base /usr/local/bin/npm /usr/local/bin/
COPY --from=node-base /usr/local/bin/npx /usr/local/bin/
COPY --from=node-base /opt/yarn-* /opt/yarn
RUN ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn

WORKDIR /app

# Ruby依存関係インストール
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Node.js依存関係インストール
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Railsサーバーポート
EXPOSE 3000

# デフォルトコマンド：Rails server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]