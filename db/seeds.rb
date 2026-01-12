# Clear existing data (development only)
if Rails.env.development?
  puts "Clearing existing data..."
  Order.destroy_all
  CouponCode.destroy_all
  PromiseFitnessKit.destroy_all
end

# Create Fitness Kits
puts "Creating fitness kits..."

kit1 = PromiseFitnessKit.create!(
  name: 'SK-1',
  description: '2lb db, xlight & light resistance tube',
  slug: 'strength-kit-1'
)

kit2 = PromiseFitnessKit.create!(
  name: 'SK-2',
  description: '3lb db, light & medium resistance tube',
  slug: 'strength-kit-2'
  )

kit3 = PromiseFitnessKit.create!(
  name: 'SK-3',
  description: '5lb db, medium & heavy resistance tube',
  slug: 'strength-kit-3'
)

kit4 = PromiseFitnessKit.create!(
  name: 'SK-4',
  description: '10lb db, heavy & extra heavy resistance tube',
  slug: 'strength-kit-4'
)

kit5 = PromiseFitnessKit.create!(
  name: 'PK-1',
  description: 'Pilates Ball & Fitness Towel',
  slug: 'pilates-kit-1'
)

kit6 = PromiseFitnessKit.create!(
  name: 'WK-1',
  description: '2 Walking/Trekking Sticks',
  slug: 'walking-trekking-1'
)

kit7 = PromiseFitnessKit.create!(
  name: 'YK-1',
  description: '2 Yoga Blocks 1 Yoga Strap',
  slug: 'yoga-kit-1'
)

puts "Created #{PromiseFitnessKit.count} fitness kits"

# Create Coupon Codes
puts "Creating coupon codes..."

unused_codes = %w[TEST1 TEST2 TEST3]
used_codes = %w[USED001 USED002 USED003 USED004 USED005]

unused_codes.each do |code|
  CouponCode.create!(code: code, usage: 'unused')
end

# Create coupons that will be used in sample orders as 'unused' first
# They will be automatically marked as 'used' when orders are created
used_codes.each do |code|
  CouponCode.create!(code: code, usage: 'unused')
end

puts "Created #{CouponCode.count} coupon codes (#{CouponCode.unused.count} unused, #{CouponCode.used.count} used)"

# Create Sample Orders
puts "Creating sample orders..."

sample_orders = [
  {
    promise_fitness_kit: kit1,
    coupon_code: CouponCode.find_by(code: 'USED001'),
    first_name: 'John',
    last_name: 'Doe',
    address1: '123 Main St',
    city: 'San Francisco',
    state: 'CA',
    zip: '94102',
    phone: '4155551234',
    email: 'john.doe@example.com'
  },
  {
    promise_fitness_kit: kit2,
    coupon_code: CouponCode.find_by(code: 'USED002'),
    first_name: 'Jane',
    last_name: 'Smith',
    address1: '456 Oak Ave',
    address2: 'Apt 3B',
    city: 'Austin',
    state: 'TX',
    zip: '78701',
    phone: '5125555678',
    email: 'jane.smith@example.com',
    description: 'Please leave at front door'
  },
  {
    promise_fitness_kit: kit3,
    coupon_code: CouponCode.find_by(code: 'USED003'),
    first_name: 'Michael',
    last_name: 'Johnson',
    address1: '789 Pine St',
    city: 'Seattle',
    state: 'WA',
    zip: '98101',
    phone: '2065559012',
    email: 'michael.j@example.com'
  }
]

sample_orders.each do |order_attrs|
  Order.create!(order_attrs)
end

puts "Created #{Order.count} sample orders"
puts "\nSeed data complete!"
puts "Fitness Kits: #{PromiseFitnessKit.count}"
puts "Coupon Codes: #{CouponCode.count} (#{CouponCode.unused.count} available)"
puts "Orders: #{Order.count}"
