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
  name: 'Beginner Strength Kit',
  description: 'Perfect for those starting their fitness journey. Includes resistance bands, workout guide, and nutrition plan.'
)

kit2 = PromiseFitnessKit.create!(
  name: 'Cardio Endurance Kit',
  description: 'Boost your cardiovascular health. Includes jump rope, interval timer, and 30-day cardio challenge guide.'
)

kit3 = PromiseFitnessKit.create!(
  name: 'Flexibility & Recovery Kit',
  description: 'Essential tools for mobility and recovery. Includes foam roller, stretching guide, and recovery protocols.'
)

puts "Created #{PromiseFitnessKit.count} fitness kits"

# Create Coupon Codes
puts "Creating coupon codes..."

unused_codes = %w[WELCOME2024 FITNESS50 NEWYEAR SPRING25 HEALTH100]
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
  },
  {
    promise_fitness_kit: kit1,
    coupon_code: CouponCode.find_by(code: 'USED004'),
    first_name: 'Sarah',
    last_name: 'Williams',
    address1: '321 Elm St',
    city: 'Boston',
    state: 'MA',
    zip: '02134',
    phone: '6175553456',
    email: 'sarah.w@example.com'
  },
  {
    promise_fitness_kit: kit2,
    coupon_code: CouponCode.find_by(code: 'USED005'),
    first_name: 'David',
    last_name: 'Brown',
    address1: '654 Maple Dr',
    city: 'Denver',
    state: 'CO',
    zip: '80202',
    phone: '7205557890',
    email: 'david.brown@example.com',
    description: 'Birthday gift - please include gift wrap'
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
