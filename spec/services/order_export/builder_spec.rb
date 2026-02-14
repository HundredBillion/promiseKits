# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'
require 'active_support/time'

RSpec.describe OrderExport::Builder, type: :service do
  # Lightweight structs that mimic the parts of the real models the builder expects.
  KitStruct = Struct.new(:name, :slug, :id)
  CouponStruct = Struct.new(:code, :id)
  OrderStruct = Struct.new(
    :id,
    :order_confirmation,
    :created_at,
    :first_name,
    :last_name,
    :email,
    :phone,
    :address1,
    :address2,
    :city,
    :state,
    :zip,
    :promise_fitness_kit,
    :coupon_code,
    :description
  )

  let(:kit) { KitStruct.new('Test Kit', 'test-kit', 42) }
  let(:coupon) { CouponStruct.new('PROMO123', 7) }

  let(:order) do
    OrderStruct.new(
      1,
      123,
      Time.utc(2026, 2, 16, 12, 0, 0),
      'Jane',
      'Doe',
      'jane@example.com',
      '1234567890',
      '1 Road',
      nil,
      'Town',
      'ST',
      '12345',
      kit,
      coupon,
      'Sample order'
    )
  end

  describe '.build_to_tempfile' do
    it 'returns a Tempfile containing a non-empty xlsx file' do
      tmp = described_class.build_to_tempfile(orders: [order])

      expect(tmp).to be_a(Tempfile)
      expect(File).to exist(tmp.path)
      expect(File.size(tmp.path)).to be > 0

      # cleanup
      tmp.close
      tmp.unlink
    end

    it 'accepts multiple orders and preserves ordering' do
      older = OrderStruct.new(2, 122, Time.utc(2026, 2, 15, 12, 0, 0), 'A', 'One', 'a@example.com', '1111111111', 'Addr1', nil, 'City', 'ST', '11111', kit, nil, nil)
      newer = OrderStruct.new(3, 124, Time.utc(2026, 2, 17, 12, 0, 0), 'B', 'Two', 'b@example.com', '2222222222', 'Addr2', nil, 'City', 'ST', '22222', kit, nil, nil)

      tmp = described_class.build_to_tempfile(orders: [older, order, newer])
      expect(tmp).to be_a(Tempfile)
      expect(File.size(tmp.path)).to be > 0

      tmp.close
      tmp.unlink
    end

    it 'formats order_confirmation with zero padding using internal helper' do
      padded = described_class.send(:formatted_order_confirmation, 123)
      expect(padded).to eq('000123')

      # nil stays nil
      expect(described_class.send(:formatted_order_confirmation, nil)).to be_nil
    end

    it 'allows a custom sheet name via opts' do
      tmp = described_class.build_to_tempfile(orders: [order], opts: { sheet_name: 'CustomSheet' })
      expect(tmp).to be_a(Tempfile)
      expect(File.size(tmp.path)).to be > 0
      tmp.close
      tmp.unlink
    end

    it 'raises ArgumentError when orders is nil' do
      expect { described_class.build_to_tempfile(orders: nil) }.to raise_error(ArgumentError)
    end
  end
end
