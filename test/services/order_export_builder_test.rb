require 'test_helper'

class OrderExportBuilderTest < ActiveSupport::TestCase
  setup do
    # create related records for orders
    @kit = PromiseFitnessKit.create!(name: 'Test Kit', description: 'desc', slug: 'test-kit')
    # Use distinct coupons per order to avoid 'already been used' validation during order creation callbacks
    @coupon1 = CouponCode.create!(code: CouponCode.generate_next_code, usage: 'unused')
    @coupon2 = CouponCode.create!(code: CouponCode.generate_next_code, usage: 'unused')

    @order1 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon1,
      first_name: 'Alice',
      last_name: 'Smith',
      address1: '1 Test St',
      city: 'Testville',
      state: 'CA',
      zip: '94102',
      phone: '4155550001',
      email: 'alice@example.com'
    )

    @order2 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon2,
      first_name: 'Bob',
      last_name: 'Jones',
      address1: '2 Test Ave',
      city: 'Testville',
      state: 'CA',
      zip: '94102',
      phone: '4155550002',
      email: 'bob@example.com'
    )
  end

  test 'builds a non-empty xlsx tempfile with headers' do
    tmp = OrderExport::Builder.build_to_tempfile(orders: Order.order(:created_at))
    assert tmp.is_a?(Tempfile), 'Expected a Tempfile to be returned'
    assert_operator File.size(tmp.path), :>, 0, 'Expected tempfile to have content'

    # The xlsx is a zipped XML; raw binary usually contains header strings.
    content = File.binread(tmp.path)
    assert_includes content, 'order_confirmation', 'Header row should include order_confirmation'
    assert_includes content, 'created_at_utc', 'Header row should include created_at_utc'

    tmp.close
    tmp.unlink
  end

  test 'rows contain formatted order confirmation and created_at in UTC' do
    tmp = OrderExport::Builder.build_to_tempfile(orders: Order.where(id: [@order1.id, @order2.id]).order(:created_at))
    assert tmp.is_a?(Tempfile)

    bin = File.binread(tmp.path)

    # Confirm that the zero-padded order confirmation appears for at least one order
    if @order1.order_confirmation.present?
      formatted = sprintf('%06d', @order1.order_confirmation.to_i)
      assert_includes bin, formatted, "Expected formatted order_confirmation #{formatted} in the xlsx binary"
    end

    # Confirm email addresses (or first names) are present in the generated file
    assert_includes bin, @order1.email, "Expected #{@order1.email} to be present in xlsx binary"
    assert_includes bin, @order2.email, "Expected #{@order2.email} to be present in xlsx binary"

    tmp.close
    tmp.unlink
  end
end
