class Admin::CouponCodesController < Admin::BaseController
  PER_PAGE = 25

  def index
    @coupons = CouponCode.all

    # Filter by status
    if params[:status].present?
      @coupons = @coupons.where(usage: params[:status])
    end

    # Search by code
    if params[:search].present?
      @coupons = @coupons.where("code LIKE ?", "%#{params[:search]}%")
    end

    # Apply cursor pagination
    @coupons = @coupons.by_cursor(params[:cursor], params[:direction] || 'next')

    # Order by id
    if params[:direction] == 'prev'
      @coupons = @coupons.order(id: :desc)
    else
      @coupons = @coupons.order(id: :asc)
    end

    # Fetch one extra to check if there are more records
    @coupons = @coupons.limit(PER_PAGE + 1).to_a
    @has_more = @coupons.size > PER_PAGE
    @coupons = @coupons.first(PER_PAGE) if @has_more
  end

  def create
    # Bulk creation support using CouponSequence reservation.
    # Accept `count` param (defaults to 1) and reserve a contiguous numeric range
    # from the sequence row so concurrent requests receive non-overlapping ranges.
    count = params[:count].to_i
    count = 1 if count < 1

    created_codes = []

    begin
      # Reserve the numeric range atomically. This returns the starting sequence number.
      start_seq = CouponSequence.default.reserve_range!(count)

      ActiveRecord::Base.transaction do
        count.times do |i|
          seq = start_seq + i
          letters = 3.times.map { ('A'..'Z').to_a.sample }.join
          code = "SK#{seq}#{letters}"
          created_codes << CouponCode.create!(code: code, usage: 'unused')
        end
      end

      if created_codes.size == 1
        redirect_to admin_coupon_codes_path, notice: "Coupon code #{created_codes.first.code} created successfully"
      else
        redirect_to admin_coupon_codes_path, notice: "#{created_codes.size} coupon codes created successfully"
      end
    rescue StandardError => e
      # Surface any errors (reservation or creation). The reservation is atomic; if creation fails
      # the sequence has already advanced — this is expected behavior for simplicity.
      redirect_to admin_coupon_codes_path, alert: "Error creating coupon code(s): #{e.message}"
    end
  end

  def destroy
    @coupon = CouponCode.find(params[:id])

    if @coupon.destroy
      redirect_to admin_coupon_codes_path, notice: "Coupon code deleted successfully"
    else
      redirect_to admin_coupon_codes_path, alert: @coupon.errors.full_messages.join(", ")
    end
  rescue ActiveRecord::InvalidForeignKey => e
    redirect_to admin_coupon_codes_path, alert: "Cannot delete coupon code because it has associated orders"
  end
end
