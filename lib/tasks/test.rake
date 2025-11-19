# frozen_string_literal: true

namespace :test do
  desc "Setup test database with master data"
  task setup: :environment do
    Rails.env = 'test'

    # DB再作成
    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke

    # スキーマ適用
    system("RAILS_ENV=test bundle exec ridgepole --config config/database.yml --env test --apply --file db/schemas/Schemafile")

    # マスターデータロード
    Rake::Task['db:seed_fu'].invoke

    puts "✅ Test database setup complete!"
  end
end
