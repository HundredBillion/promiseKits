require "test_helper"

class PromiseFitnessKitTest < ActiveSupport::TestCase
  test "should not save without name" do
    kit = PromiseFitnessKit.new(description: "Test description")
    assert_not kit.save, "Saved kit without name"
    assert_includes kit.errors[:name], "can't be blank"
  end

  test "should not save without description" do
    kit = PromiseFitnessKit.new(name: "Test Kit")
    assert_not kit.save, "Saved kit without description"
    assert_includes kit.errors[:description], "can't be blank"
  end

  test "should not save duplicate name" do
    PromiseFitnessKit.create!(name: "Unique Kit", description: "Description")
    kit = PromiseFitnessKit.new(name: "Unique Kit", description: "Another description")
    assert_not kit.save, "Saved kit with duplicate name"
    assert_includes kit.errors[:name], "has already been taken"
  end

  test "should have many orders" do
    kit = PromiseFitnessKit.reflect_on_association(:orders)
    assert_equal :has_many, kit.macro
  end

  test "should not delete kit with associated orders" do
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

    assert_not kit.destroy, "Kit was destroyed even though it has associated orders"
    assert_includes kit.errors.full_messages.join, "Cannot delete record because dependent orders exist"
  end

  test "ordered_by_name scope returns kits alphabetically" do
    PromiseFitnessKit.create!(name: "Zebra Kit", description: "Last")
    PromiseFitnessKit.create!(name: "Alpha Kit", description: "First")
    PromiseFitnessKit.create!(name: "Beta Kit", description: "Second")

    kits = PromiseFitnessKit.ordered_by_name
    assert_equal "Alpha Kit", kits.first.name
    assert_equal "Zebra Kit", kits.last.name
  end

  test "to_s returns name" do
    kit = PromiseFitnessKit.new(name: "Test Kit", description: "Description")
    assert_equal "Test Kit", kit.to_s
  end
end
