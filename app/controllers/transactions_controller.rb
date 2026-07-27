class TransactionsController < ApplicationController
  
  PER_PAGE_OPTIONS = [20, 50, 100, 250].freeze

  # Nested under /accounts/:account_id/transactions this renders one account's
  # transactions (the account subnav's Transactions tab); unnested it renders
  # every account's, alongside the add/import forms.
  def index
    @account = Account.find(params[:account_id]) if params[:account_id]
    scope = @account ? @account.transactions : Transaction.all

    # Every symbol available to filter by — the unfiltered scope's, so the
    # dropdown's options don't disappear as the user narrows the list.
    @symbols = Asset.where(id: scope.select(:asset_id)).order(:symbol).pluck(:symbol)
    @selected_symbols = Array(params[:symbols]).map(&:to_s) & @symbols
    scope = scope.where(asset_id: Asset.where(symbol: @selected_symbols)) if @selected_symbols.any?

    # Only honor a per_page the select offers, so the param can't ask for an
    # unbounded page.
    @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : PER_PAGE_OPTIONS.first
    @total_count = scope.count
    @total_pages = [(@total_count / @per_page.to_f).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)

    # `orders` sanitizes params[:order] against TransactionACL#orders, so an
    # unpermitted sort key raises rather than reaching the query.
    @transactions = scope.sort(orders).limit(@per_page).offset((@page - 1) * @per_page)
  end

  # Newest first until a header is clicked. Private so it isn't routable.
  private def default_orders
    {executed_at: :desc}
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
