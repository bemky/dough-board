class TransactionsController < ApplicationController
  
  def index
    @transactions = Transaction.order(executed_at: :desc)
    @portfolio = @transactions.portfolio
  end

  # standardapi provides show/new/create/update but no edit action, so define
  # one that populates the resource ivar for edit.html.erb's form.
  def edit
    instance_variable_set("@#{model.model_name.singular}", resource)
  end

  # Import a CSV of executed trades (Robinhood format) into the selected account.
  # Dedups on account_id + foreign_id (the broker's order_id) so re-imports are safe.
  SIDE_MAP = {
    "buy" => "buy", "buy_to_open" => "buy",
    "sell" => "sale", "sell_to_close" => "sale"
  }.freeze

  def import
    unless params[:file].respond_to?(:read) && params[:account_id].present?
      redirect_to root_path, alert: "Choose an account and a CSV file to import." and return
    end

    created = updated = skipped = errored = 0

    CSV.parse(params[:file].read, headers: true).each do |row|
      if row["asset_type"] == "option"
        skipped += 1
        next
      end

      side = SIDE_MAP[row["side"]]
      unless side
        skipped += 1
        next
      end

      transaction = Transaction.find_or_initialize_by(
        account_id: params[:account_id],
        foreign_id: row["order_id"]
      )
      new_record = transaction.new_record?

      transaction.assign_attributes(
        symbol: row["symbol"],
        type: side,
        executed_at: row["fill_date"],
        quantity: row["quantity"],
        value: row["gross_amount"]
      )

      begin
        if transaction.save
          new_record ? created += 1 : updated += 1
        else
          errored += 1
        end
      rescue => e
        # One symbol's quote/split fetch failing must not abort the whole import.
        Rails.logger.warn("Import row failed (#{row["symbol"]} #{row["order_id"]}): #{e.class}: #{e.message}")
        errored += 1
      end
    end

    notice = "Import complete: #{created} created, #{updated} updated, " \
             "#{skipped} skipped, #{errored} errored."
    redirect_to root_path, notice: notice
  end

end
