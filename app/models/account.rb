class Account < ApplicationRecord
  has_many :transactions

  validates :name, presence: true

  def label
    "#{provider} - #{name}"
  end
end
