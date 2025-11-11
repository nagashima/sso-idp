# frozen_string_literal: true

namespace :ridgepole do
  # rake ridgepole:apply
  desc 'Apply database schema'
  task apply: :environment do
    ridgepole('--apply', "--env #{Rails.env}", "--file #{schema_file}")
  end

  private def schema_file
    Rails.root.join('db/schemas/Schemafile')
  end

  private def config_string
    JSON.dump(ActiveRecord::Base.connection_db_config.configuration_hash).gsub(/\"/, ' ')
  end

  private def ridgepole(*options)
    command = ['bundle exec ridgepole', "--config \"#{config_string}\""]
    system [command + options].join(' ')
  end
end
