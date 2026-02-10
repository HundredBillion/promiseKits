# frozen_string_literal: true

# Model to manage numeric sequence reservations for coupon code generation.
#
# Purpose:
# - Provide an atomic way to reserve contiguous numeric ranges for coupon codes.
# - Allow manual control of the last used sequence (so an admin can "jump" generations).
#
# Usage:
#   seq = CouponSequence.default
#   start_number = seq.reserve_range!(10) # reserves 10 numbers, returns starting number
#   # next numbers reserved will be start_number, start_number+1, ..., start_number+9
#
#   seq.set_last_sequence!(42) # sets last_sequence to 42; next reservation will start at 43
#
class CouponSequence < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :last_sequence, presence: true, numericality: { only_integer: true }

  # Reserve a contiguous numeric range of size `count` and return the starting number.
  # This method is atomic: it locks the sequence row so concurrent callers get disjoint ranges.
  #
  # Raises:
  # - ArgumentError if count is less than 1
  # - ActiveRecord::RecordNotFound if the record no longer exists
  # - ActiveRecord::ActiveRecordError for DB-level issues
  def reserve_range!(count)
    count = count.to_i
    raise ArgumentError, "count must be >= 1" if count < 1

    self.class.transaction do
      # Lock the row for update so concurrent transactions wait and get distinct ranges.
      seq = self.class.lock.find_by!(id: id)

      start_seq = seq.last_sequence + 1
      seq.update!(last_sequence: seq.last_sequence + count)

      start_seq
    end
  end

  # Forcefully set the last_sequence to a specific value.
  # After calling this, the next reservation will start at (value + 1).
  #
  # Accepts integers or strings that can be coerced to integers.
  def set_last_sequence!(value)
    value = value.to_i
    update!(last_sequence: value)
  end

  # Convenience: get or create the default named sequence row.
  # The default row uses name == 'default' and initial last_sequence == 999,
  # so the first generated numeric value will be 1000 if no other coupons exist.
  def self.default
    find_or_create_by!(name: 'default')
  end
end
