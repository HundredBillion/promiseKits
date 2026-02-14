# frozen_string_literal: true

# Define the controller directly under the Admin:: namespace without opening a module.
# Using `module Admin` in this file conflicts with the `Admin` model constant (class Admin),
# which can produce "type error admin is not a module" in some loading scenarios.
class Admin::OrderSequencesController < Admin::BaseController
  # Controller to view and update the order confirmation sequence used when
  # generating `order_confirmation` numbers for Order records.
  #
  # This is intentionally lightweight: it exposes a `show` action so admins can
  # inspect the current sequence and an `update` action to set the sequence to
  # a new last value (so the next reserved value will be `last_value + 1`).
  #
  # Routes (example):
  #   resource :order_sequence, only: [:show, :update], controller: 'admin/order_sequences'
  #
  # Example usage:
  #   GET  /admin/order_sequence   -> Admin::OrderSequencesController#show
  #   PATCH/PUT /admin/order_sequence -> Admin::OrderSequencesController#update
  #

  # Show the order_confirmation sequence row so admins can inspect it.
  def show
    @sequence = Sequence.order_confirmation
  end

  # Update the order_confirmation sequence's last_value.
  # Expects params[:order_sequence][:last_value] to be present.
  # Redirects back to the admin dashboard on success or failure.
  def update
    @sequence = Sequence.order_confirmation

    if params[:order_sequence].present? && params[:order_sequence][:last_value].present?
      begin
        @sequence.set_last_value!(params[:order_sequence][:last_value])
        redirect_to admin_dashboard_path, notice: "Order confirmation sequence updated. Next confirmation will start at #{@sequence.last_value + 1}"
      rescue StandardError => e
        redirect_to admin_dashboard_path, alert: "Unable to update order confirmation sequence: #{e.message}"
      end
    else
      redirect_to admin_dashboard_path, alert: "Please provide a valid sequence value"
    end
  end

  private

  # Permit the last_value param for strong-parameter protection.
  def order_sequence_params
    params.require(:order_sequence).permit(:last_value)
  end
end
