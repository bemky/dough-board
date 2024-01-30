module TransactionACL

  def attributes
    [
      :executed_at,
      :symbol,
      :vendor,
      :quantity,
      :value,
      :type
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