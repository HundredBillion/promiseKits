class PromiseFitnessKit < ApplicationRecord
  # Associations
  has_many :orders, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  # Scopes
  scope :ordered_by_name, -> { order(:name) }

  # Instance Methods
  def to_s
    name
  end
end
