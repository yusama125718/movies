class Cinema < ApplicationRecord
  has_many :schedules, dependent: :destroy
end
