# frozen_string_literal: true
#
# Sequence
#
# Purpose:
# - A tiny table-backed sequence generator that provides atomic,
#   incrementing numeric values for various application concerns
#   (for example: `order_confirmation` numbers).
#
# Why use this:
# - On SQLite, write transactions are serialized, so updating a single-row
#   counter inside a transaction provides a safe, race-free way to hand
#   out monotonic unique numbers without relying on MAX(...) queries.
# - This model centralizes sequence logic and allows admins to manually
#   set the last value (so you can "jump" generations or skip ranges).
#
# Usage examples:
#
#   # Reserve a single value for order confirmations:
#   seq = Sequence.for('order_confirmation')
#   start = seq.reserve_range!(1)    # returns the allocated number
#
#   # Reserve a contiguous block of 10 values:
#   start = seq.reserve_range!(10)   # returns the first number in the reserved block
#   # reserved values: start, start+1, ..., start+9
#
#   # Atomically set the sequence (admin action):
#   Sequence.for('order_confirmation').set_last_value!(5000)
#   # next reserved value will be 5001
#
class Sequence < ApplicationRecord
  # Basic validations
  validates :name, presence: true, uniqueness: true
  validates :last_value,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Convenience scope/alias for the :order_confirmation sequence
  def self.order_confirmation
    for_name('order_confirmation')
  end

  # Find or create a sequence row by name. Ensures a row exists.
  #
  # Example:
  #   seq = Sequence.for('order_confirmation')
  #
  def self.for_name(name)
    find_or_create_by!(name: name.to_s) do |s|
      s.last_value = 0
    end
  end

  # Backwards-compatible alias so existing callers continue to work.
  # Calling `Sequence.for(...)` with an explicit receiver (e.g., `Sequence.for(...)`)
  # will still be supported; internal unqualified calls were updated to avoid
  # the Ruby `for` keyword parsing ambiguity.
  def self.for(name)
    for_name(name)
  end

  # Reserve a contiguous numeric range of size `count` and return the starting value.
  #
  # This operation is performed inside a transaction and updates the sequence row
  # atomically so concurrent callers will receive disjoint ranges.
  #
  # Returns:
  #   Integer - the first number reserved (the caller may use `start + i` for subsequent numbers)
  #
  # Raises:
  #   ArgumentError if count < 1
  #   ActiveRecord::RecordNotFound if the row disappears between calls (very unlikely)
  #
  def reserve_range!(count = 1)
    count = count.to_i
    raise ArgumentError, 'count must be >= 1' if count < 1

    self.class.transaction do
      # Lock the row for update so concurrent transactions wait.
      # On SQLite the transaction serialization guarantees atomicity for the update.
      seq = self.class.lock.find_by!(id: id)

      start_value = seq.last_value + 1
      # Use update! to persist the new last_value (and run validations).
      seq.update!(last_value: seq.last_value + count)

      start_value
    end
  end

  # Forcefully set the last_value to a specific value.
  # After calling this, the next reservation will start at (value + 1).
  #
  # Accepts integers or strings coercible to integers.
  #
  def set_last_value!(value)
    value = value.to_i
    update!(last_value: value)
  end

  # Non-destructive peek at the next value that would be allocated.
  # Does NOT modify the sequence row.
  #
  def next_value
    last_value.to_i + 1
  end

  # Class-level helper that finds (or creates) the sequence and reserves a range
  # in one call. Useful for concise usage in other parts of the app:
  #
  #   start = Sequence.reserve_for('order_confirmation', 3)
  #
  def self.reserve_for(name, count = 1)
    seq = for_name(name)
    seq.reserve_range!(count)
  end

  # Optional: atomic increment using a single UPDATE SQL statement that avoids
  # loading the row first. This can be used if you want minimal round-trips.
  # It is intentionally left as a private helper in case you prefer that style.
  #
  # Note: update_all bypasses validations/callbacks but is atomic at the SQL
  # statement level. We perform a reload after the update to read back the
  # new last_value.
  #
  private

  def atomic_increment!(amount = 1)
    amount = amount.to_i
    raise ArgumentError, 'amount must be >= 1' if amount < 1

    self.class.transaction do
      # Use SQL-level update to increment in-place.
      self.class.where(id: id).update_all("last_value = last_value + #{amount}")
      reload
    end
  end
end
