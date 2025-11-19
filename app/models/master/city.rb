# frozen_string_literal: true

class Master::City < ApplicationRecord
  self.table_name = 'master_cities'

  belongs_to :master_prefecture, class_name: 'Master::Prefecture', foreign_key: :master_prefecture_id

  validates :name, presence: true
  validates :kana_name, presence: true
  validates :latitude, presence: true
  validates :longitude, presence: true
  validates :search_text, presence: true
end
