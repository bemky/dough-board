class Exchange < ApplicationRecord

  has_many :assets

  normalizes :code, with: -> code { code.upcase }

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  def label
    "#{code} - #{name}"
  end

end
