class AccountsController < ApplicationController

  # StandardAPI has no `edit` action, so define one that loads @account for the
  # edit template (mirrors its `show`).
  def edit
    @account = resource
  end

end
