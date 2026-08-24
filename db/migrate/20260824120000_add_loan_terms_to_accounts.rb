class AddLoanTermsToAccounts < ActiveRecord::Migration[8.1]
  def change
    # What a loan was written as: principal, rate, term and start date, plus
    # which kind of debt it is. Only read when positions_source is "amortized";
    # every other account leaves it null.
    add_column :accounts, :loan_terms, :json
  end
end
