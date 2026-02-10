class Admin::CouponSequencesController < Admin::BaseController
  # Show the current default coupon sequence.
  # Renders a simple view where admins can inspect and update the sequence.
  def show
    @sequence = CouponSequence.default
  end

  # Update the default sequence's `last_sequence` value.
  # Expects params[:coupon_sequence][:last_sequence] to be present.
  # Redirects back to the coupon codes index with a notice on success,
  # or with an alert on failure.
  def update
    @sequence = CouponSequence.default

    if params[:coupon_sequence].present? && params[:coupon_sequence][:last_sequence].present?
      begin
        # allow strings/numerics; CouponSequence#set_last_sequence! will coerce to integer
        @sequence.set_last_sequence!(params[:coupon_sequence][:last_sequence])
        redirect_to admin_coupon_codes_path, notice: "Sequence updated. Next coupon will start at #{@sequence.last_sequence + 1}"
      rescue StandardError => e
        redirect_to admin_coupon_codes_path, alert: "Unable to update sequence: #{e.message}"
      end
    else
      redirect_to admin_coupon_codes_path, alert: "Please provide a valid sequence value"
    end
  end

  private

  # Strong params in case future attributes are added.
  def coupon_sequence_params
    params.require(:coupon_sequence).permit(:last_sequence)
  end
end
