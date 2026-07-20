module TransactionACL

  def attributes
    [
      :executed_at,
      :symbol,
      :account_id,
      :quantity,
      :value,
      :type,
      :foreign_id
    ]
  end

  def nested
    [
    ]
  end

  def orders
    [
    ]
  end

  def includes
    {}
  end

end