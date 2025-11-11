# frozen_string_literal: true

namespace :master_data do
  desc 'Export master data to seed-fu format'
  task export_fixtures: :environment do
    fixtures_dir = Rails.root.join('db', 'fixtures')
    FileUtils.mkdir_p(fixtures_dir) unless Dir.exist?(fixtures_dir)

    # master_prefectures
    if ActiveRecord::Base.connection.tables.include?('master_prefectures')
      puts '📝 Exporting master_prefectures...'

      prefectures = ActiveRecord::Base.connection.execute('SELECT * FROM master_prefectures ORDER BY id')

      File.open(fixtures_dir.join('001_master_prefectures.rb'), 'w') do |f|
        f.puts '# frozen_string_literal: true'
        f.puts ''
        f.puts 'Master::Prefecture.seed(:id, ['

        prefectures.each_with_index do |row, index|
          id = row[0]
          name = row[1]
          kana_name = row[2]

          comma = index < prefectures.count - 1 ? ',' : ''
          f.puts "  { id: #{id}, name: #{name.inspect}, kana_name: #{kana_name.inspect} }#{comma}"
        end

        f.puts '])'
      end

      puts "✅ Exported to db/fixtures/001_master_prefectures.rb (#{prefectures.count} records)"
    else
      puts '⚠️  master_prefectures table not found'
    end

    # master_cities
    if ActiveRecord::Base.connection.tables.include?('master_cities')
      puts '📝 Exporting master_cities...'

      cities = ActiveRecord::Base.connection.execute('SELECT * FROM master_cities ORDER BY id')

      File.open(fixtures_dir.join('002_master_cities.rb'), 'w') do |f|
        f.puts '# frozen_string_literal: true'
        f.puts ''
        f.puts 'Master::City.seed(:id, ['

        cities.each_with_index do |row, index|
          id = row[0]
          master_prefecture_id = row[1]
          name = row[2]
          kana_name = row[3]
          county_name = row[4]
          kana_county_name = row[5]
          latitude = row[6]
          longitude = row[7]
          search_text = row[8]
          ordinance_designated = row[9]
          ward_parent_master_city_id = row[10]

          comma = index < cities.count - 1 ? ',' : ''
          f.puts "  { id: #{id}, master_prefecture_id: #{master_prefecture_id}, name: #{name.inspect}, kana_name: #{kana_name.inspect}, county_name: #{county_name.inspect}, kana_county_name: #{kana_county_name.inspect}, latitude: #{latitude}, longitude: #{longitude}, search_text: #{search_text.inspect}, ordinance_designated: #{ordinance_designated}, ward_parent_master_city_id: #{ward_parent_master_city_id.inspect} }#{comma}"
        end

        f.puts '])'
      end

      puts "✅ Exported to db/fixtures/002_master_cities.rb (#{cities.count} records)"
    else
      puts '⚠️  master_cities table not found'
    end
  end
end
