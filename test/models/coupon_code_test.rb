require "test_helper"

class CouponCodeTest < ActiveSupport::TestCase
  test "should not save without code" do
    coupon = CouponCode.new(usage: "unused")
    assert_not coupon.save, "Saved coupon without code"
    assert_includes coupon.errors[:code], "can't be blank"
  end

  test "should not save duplicate code" do
    CouponCode.create!(code: "DUPLICATE", usage: "unused")
    coupon = CouponCode.new(code: "DUPLICATE", usage: "unused")
    assert_not coupon.save, "Saved coupon with duplicate code"
    assert_includes coupon.errors[:code], "has already been taken"
  end

  test "should validate case-insensitive uniqueness" do
    CouponCode.create!(code: "TESTCODE", usage: "unused")
    coupon = CouponCode.new(code: "testcode", usage: "unused")
    assert_not coupon.save, "Saved coupon with duplicate code (different case)"
    assert_includes coupon.errors[:code], "has already been taken"
  end

  test "should normalize code to uppercase" do
    coupon = CouponCode.create!(code: "lowercase123", usage: "unused")
    assert_equal "LOWERCASE123", coupon.code
  end

  test "should default usage to unused" do
    coupon = CouponCode.new(code: "TEST123")
    assert_equal "unused", coupon.usage
  end

  test "should validate usage inclusion" do
    coupon = CouponCode.new(code: "TEST123", usage: "invalid")
    assert_not coupon.save, "Saved coupon with invalid usage"
    assert_includes coupon.errors[:usage], "is not included in the list"
  end

  test "unused? returns true for unused coupons" do
    coupon = CouponCode.new(code: "TEST123", usage: "unused")
    assert coupon.unused?, "unused? should return true for unused coupons"
  end

  test "used? returns true for used coupons" do
    coupon = CouponCode.new(code: "TEST123", usage: "used")
    assert coupon.used?, "used? should return true for used coupons"
  end

  test "mark_as_used! changes usage to used" do
    coupon = CouponCode.create!(code: "TEST123", usage: "unused")
    coupon.mark_as_used!
    assert_equal "used", coupon.usage
    assert coupon.used?
  end

  test "unused scope returns only unused coupons" do
    CouponCode.create!(code: "UNUSED1", usage: "unused")
    CouponCode.create!(code: "USED1", usage: "used")
    CouponCode.create!(code: "UNUSED2", usage: "unused")

    unused_coupons = CouponCode.unused
    assert_equal 2, unused_coupons.count
    assert unused_coupons.all?(&:unused?)
  end

  test "used scope returns only used coupons" do
    CouponCode.create!(code: "UNUSED1", usage: "unused")
    CouponCode.create!(code: "USED1", usage: "used")
    CouponCode.create!(code: "USED2", usage: "used")

    used_coupons = CouponCode.used
    assert_equal 2, used_coupons.count
    assert used_coupons.all?(&:used?)
  end

  test "should have many orders" do
    coupon = CouponCode.reflect_on_association(:orders)
    assert_equal :has_many, coupon.macro
  end

  test "should not delete coupon with associated orders" do
    kit = PromiseFitnessKit.create!(name: "Test Kit", description: "Description")
    coupon = CouponCode.create!(code: "TEST123", usage: "unused")
    Order.create!(
      promise_fitness_kit: kit,
      coupon_code: coupon,
      first_name: "John",
      last_name: "Doe",
      address1: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip: "94102",
      phone: "4155551234",
      email: "john@example.com"
    )

    assert_not coupon.destroy, "Coupon was destroyed even though it has associated orders"
    assert_includes coupon.errors.full_messages.join, "Cannot delete record because dependent orders exist"
  end
end
