class Movie < ApplicationRecord
  belongs_to :cinema
  has_many :schedules, dependent: :destroy
end
