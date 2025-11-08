class Movie < ApplicationRecord
  has_many :schedules, dependent: :destroy
end
