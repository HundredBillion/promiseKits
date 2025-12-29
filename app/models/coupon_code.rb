class CouponCode < ApplicationRecord
  # Associations
  has_many :orders, dependent: :restrict_with_error

  # Validations
  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :usage, presence: true, inclusion: { in: %w[unused used] }

  # Callbacks
  before_validation :normalize_code

  # Scopes
  scope :unused, -> { where(usage: 'unused') }
  scope :used, -> { where(usage: 'used') }

  # Instance Methods
  def unused?
    usage == 'unused'
  end

  def used?
    usage == 'used'
  end

  def mark_as_used!
    update!(usage: 'used')
  end

  private

  def normalize_code
    self.code = code.to_s.upcase.strip if code.present?
  end
end
