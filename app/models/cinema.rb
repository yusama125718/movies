class Cinema < ApplicationRecord
  has_many :movies, dependent: :destroy
end
