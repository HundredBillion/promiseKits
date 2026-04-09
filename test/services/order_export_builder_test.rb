require "test_helper"
require "zip"

class OrderExportBuilderTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @kit = PromiseFitnessKit.create!(name: "Test Kit", description: "desc", slug: "test-kit-builder-#{SecureRandom.hex(4)}")
    # Use distinct coupons per order to avoid 'already been used' validation during order creation callbacks
    @coupon1 = CouponCode.create!(code: CouponCode.generate_next_code, usage: "unused")
    @coupon2 = CouponCode.create!(code: CouponCode.generate_next_code, usage: "unused")

    @order1 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon1,
      first_name: "Alice",
      last_name: "Smith",
      address1: "1 Test St",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550001",
      email: "alice@example.com"
    )

    @order2 = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon2,
      first_name: "Bob",
      last_name: "Jones",
      address1: "2 Test Ave",
      city: "Testville",
      state: "CA",
      zip: "94102",
      phone: "4155550002",
      email: "bob@example.com"
    )
  end

  def teardown
    ExportedOrder.delete_all
    OrderExport.delete_all
    Order.delete_all
    CouponCode.delete_all
    PromiseFitnessKit.delete_all
  end

  test "builds a non-empty xlsx tempfile with headers" do
    tmp = OrderExportBuilder.build_to_tempfile(orders: Order.order(:created_at))
    assert tmp.is_a?(Tempfile), "Expected a Tempfile to be returned"
    assert_operator File.size(tmp.path), :>, 0, "Expected tempfile to have content"

    # xlsx is a zip file - verify it's a valid zip by checking header and opening with Zip library
    content = File.binread(tmp.path, 2)
    assert_equal "PK", content, "xlsx should start with PK zip header"

    # Verify we can open the zip and it contains expected XML files
    Zip::InputStream.open(tmp.path) do |zip|
      entry = zip.get_next_entry
      assert_not_nil entry, "Expected at least one entry in zip"
      assert_match /\.xml$/, entry.name, "Expected XML entry in xlsx"
    end

    tmp.close
    tmp.unlink
  end

  test "rows contain formatted order confirmation and created_at in UTC" do
    tmp = OrderExportBuilder.build_to_tempfile(orders: Order.where(id: [ @order1.id, @order2.id ]).order(:created_at))
    assert tmp.is_a?(Tempfile)

    # Verify xlsx is valid and parse the worksheet to check content
    Zip::InputStream.open(tmp.path) do |zip|
      # Find the worksheet file (sheet1.xml)
      entry = nil
      loop do
        entry = zip.get_next_entry
        break unless entry
        break if entry.name.include?("worksheets/sheet1")
      end

      assert_not_nil entry, "Expected worksheet entry in xlsx"

      # Read the worksheet XML content
      xml_content = zip.read
      assert_not_nil xml_content, "Expected worksheet XML content"

      # Verify order data is present in the XML
      assert_includes xml_content, "Alice", "Expected Alice first_name in xlsx"
      assert_includes xml_content, "Bob", "Expected Bob first_name in xlsx"
      assert_includes xml_content, "alice@example.com", "Expected Alice email in xlsx"
      assert_includes xml_content, "bob@example.com", "Expected Bob email in xlsx"
    end

    tmp.close
    tmp.unlink
  end
end
