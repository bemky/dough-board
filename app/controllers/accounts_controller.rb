class AccountsController < ApplicationController

  def index
    # sort and not order because it's method not attribute
    @accounts = Account.all.sort_by { |account| -account.value }
  end

  # StandardAPI has no `edit` action, so define one that loads @account for the
  # edit template (mirrors its `show`).
  def edit
    @account = resource
  end

end
