# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OrderExport, type: :model do
  # Helper to create a minimal valid PromiseFitnessKit and CouponCode for orders
  def create_kit(attrs = {})
    PromiseFitnessKit.create!(
      { name: "Spec Kit #{SecureRandom.hex(4)}", description: 'Spec kit', slug: "spec-kit-#{SecureRandom.hex(6)}" }.merge(attrs)
    )
  end

  def create_coupon(code = nil)
    CouponCode.create!(code: code || "SPEC#{SecureRandom.hex(6)}", usage: 'unused')
  end

  def build_order(created_at:)
    Order.create!(
      promise_fitness_kit: create_kit,
      coupon_code: create_coupon,
      first_name: 'Spec',
      last_name: 'Tester',
      address1: '1 Spec Lane',
      city: 'Testville',
      state: 'CA',
      zip: '94107',
      phone: '4155551234',
      email: "spec+#{SecureRandom.hex(4)}@example.com",
      created_at: created_at,
      updated_at: created_at
    )
  end

  describe '#reserve_orders!' do
    before do
      OrderExport.delete_all
      ExportedOrder.delete_all
      Order.delete_all
    end

    it 'raises ArgumentError when ends_at is nil' do
      export = OrderExport.create!(status: 'pending', scheduled_for: Time.current.utc)
      expect { export.reserve_orders!(ends_at: nil) }.to raise_error(ArgumentError)
    end

    it 'reserves orders with created_at > last_successful.ends_at and <= ends_at' do
      # Anchor times in UTC for deterministic behavior
      base = Time.utc(2026, 2, 16, 12, 0, 0)

      # Create three orders: one before, one inside window, one at the upper bound
      o_before = build_order(created_at: base - 2.days)
      o_inside = build_order(created_at: base - 1.day)
      o_at_end  = build_order(created_at: base)

      # Create a prior successful export whose ends_at is between o_before and o_inside
      prev_end = base - 1.5.days
      OrderExport.create!(
        status: 'succeeded',
        scheduled_for: prev_end,
        started_at: prev_end - 60,
        ends_at: prev_end,
        filename: 'previous.xlsx'
      )

      # New export attempting to reserve up to `base`
      export = OrderExport.create!(status: 'pending', scheduled_for: base)

      reserved = export.reserve_orders!(ends_at: base)

      # The export should be moved to running and have started_at/ends_at set
      expect(export.reload.running?).to be true
      expect(export.started_at).to be_present
      expect(export.ends_at).to eq(base)

      # Should reserve only orders with created_at > prev_end and <= base => o_inside and o_at_end
      reserved_ids = reserved.map(&:id)
      expect(reserved_ids).to contain_exactly(o_inside.id, o_at_end.id)

      # ExportedOrder rows should exist for those reserved orders
      expect(export.exported_orders.pluck(:order_id).sort).to eq(reserved_ids.sort)
    end

    it 'uses last_successful export when starts_at is omitted' do
      now = Time.utc(2026, 3, 1, 10, 0, 0)
      prev_end = now - 2.days

      # Create prior successful export
      OrderExport.create!(status: 'succeeded', scheduled_for: prev_end, started_at: prev_end - 60, ends_at: prev_end)

      a = build_order(created_at: prev_end - 1.hour) # excluded
      b = build_order(created_at: prev_end + 1.second) # included
      c = build_order(created_at: now) # included

      export = OrderExport.create!(status: 'pending', scheduled_for: now)

      reserved = export.reserve_orders!(ends_at: now)

      expect(reserved.pluck(:id)).to include(b.id, c.id)
      expect(reserved.pluck(:id)).not_to include(a.id)
    end

    it 'skips orders already reserved by another export (handles uniqueness conflicts)' do
      anchor = Time.utc(2026, 4, 5, 9, 0, 0)

      o1 = build_order(created_at: anchor - 2.hours)
      o2 = build_order(created_at: anchor - 1.hour)

      # Simulate another export that already exported o1
      other = OrderExport.create!(status: 'succeeded', scheduled_for: anchor - 3.hours, started_at: anchor - 3.hours, ends_at: anchor - 2.hours)
      ExportedOrder.create!(order_export: other, order: o1)

      export = OrderExport.create!(status: 'pending', scheduled_for: anchor)
      reserved = export.reserve_orders!(ends_at: anchor)

      # o1 should be skipped; only o2 reserved
      expect(reserved.pluck(:id)).to eq([o2.id])
      expect(export.exported_orders.count).to eq(1)
      expect(export.exported_orders.first.order_id).to eq(o2.id)
    end

    it 'returns orders in chronological order' do
      anchor = Time.utc(2026, 5, 10, 8, 0, 0)

      o_earliest = build_order(created_at: anchor - 3.hours)
      o_middle   = build_order(created_at: anchor - 2.hours)
      o_latest   = build_order(created_at: anchor - 1.hour)

      export = OrderExport.create!(status: 'pending', scheduled_for: anchor)
      reserved = export.reserve_orders!(ends_at: anchor)

      expect(reserved.map(&:id)).to eq([o_earliest.id, o_middle.id, o_latest.id])
    end
  end
end
