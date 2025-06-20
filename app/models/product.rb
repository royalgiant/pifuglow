class Product < ApplicationRecord
  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end