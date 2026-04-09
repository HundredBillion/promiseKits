require_relative "test_helper"

class PromiseFitnessKitTest < ActiveSupport::TestCase
  def setup
    @original_slugs = []
  end

  def teardown
    Order.delete_all
    CouponCode.delete_all
    PromiseFitnessKit.delete_all
  end
  test "should not save without name" do
    kit = PromiseFitnessKit.new(description: "Test description", slug: "test-slug")
    assert_not kit.save, "Saved kit without name"
    assert_includes kit.errors[:name], "can't be blank"
  end

  test "should not save without description" do
    kit = PromiseFitnessKit.new(name: "Test Kit #{SecureRandom.hex(4)}", slug: "test-kit-#{SecureRandom.hex(4)}")
    assert_not kit.save, "Saved kit without description"
    assert_includes kit.errors[:description], "can't be blank"
  end

  test "should not save duplicate name" do
    PromiseFitnessKit.create!(name: "Unique Kit", description: "Description", slug: "unique-kit")
    kit = PromiseFitnessKit.new(name: "Unique Kit", description: "Another description", slug: "unique-kit-2")
    assert_not kit.save, "Saved kit with duplicate name"
    assert_includes kit.errors[:name], "has already been taken"
  end

  test "should have many orders" do
    kit = PromiseFitnessKit.reflect_on_association(:orders)
    assert_equal :has_many, kit.macro
  end

  test "should not delete kit with associated orders" do
    kit = PromiseFitnessKit.create!(name: "Test Kit Delete", description: "Description", slug: "test-kit-delete-#{SecureRandom.hex(4)}")
    coupon = CouponCode.create!(code: "SK1000AAA", usage: "unused")
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
    PromiseFitnessKit.create!(name: "Zebra Kit", description: "Last", slug: "zebra-kit-#{SecureRandom.hex(4)}")
    PromiseFitnessKit.create!(name: "Alpha Kit", description: "First", slug: "alpha-kit-#{SecureRandom.hex(4)}")
    PromiseFitnessKit.create!(name: "Beta Kit", description: "Second", slug: "beta-kit-#{SecureRandom.hex(4)}")

    kits = PromiseFitnessKit.ordered_by_name
    assert_equal "Alpha Kit", kits.first.name
    assert_equal "Zebra Kit", kits.last.name
  end

  test "to_s returns name" do
    kit = PromiseFitnessKit.new(name: "Test Kit", description: "Description", slug: "test-kit-tos-#{SecureRandom.hex(4)}")
    assert_equal "Test Kit", kit.to_s
  end

  test "should not save without slug" do
    kit = PromiseFitnessKit.new(name: "Test Kit", description: "Test Description")
    assert_not kit.save, "Saved kit without slug"
    assert_includes kit.errors[:slug], "can't be blank"
  end

  test "should not save with duplicate slug" do
    unique = SecureRandom.hex(4)
    PromiseFitnessKit.create!(name: "Kit 1", description: "Desc 1", slug: "test-slug-#{unique}")
    kit = PromiseFitnessKit.new(name: "Kit 2", description: "Desc 2", slug: "test-slug-#{unique}")
    assert_not kit.save, "Saved kit with duplicate slug"
    assert_includes kit.errors[:slug], "has already been taken"
  end

  test "should not save slug with uppercase letters" do
    kit = PromiseFitnessKit.new(name: "Test", description: "Test", slug: "test-Kit-#{SecureRandom.hex(4)}")
    assert_not kit.save, "Saved kit with uppercase in slug"
    assert_includes kit.errors[:slug], "must contain only lowercase letters, numbers, and hyphens"
  end

  test "should not save slug with spaces" do
    kit = PromiseFitnessKit.new(name: "Test", description: "Test", slug: "test kit #{SecureRandom.hex(4)}")
    assert_not kit.save, "Saved kit with spaces in slug"
    assert_includes kit.errors[:slug], "must contain only lowercase letters, numbers, and hyphens"
  end

  test "should not save slug with underscores" do
    kit = PromiseFitnessKit.new(name: "Test", description: "Test", slug: "test_kit_#{SecureRandom.hex(4)}")
    assert_not kit.save, "Saved kit with underscores in slug"
    assert_includes kit.errors[:slug], "must contain only lowercase letters, numbers, and hyphens"
  end

  test "should save valid slug" do
    kit = PromiseFitnessKit.new(name: "Test", description: "Test", slug: "test-kit-123-#{SecureRandom.hex(4)}")
    assert kit.save, "Could not save kit with valid slug"
  end
end
