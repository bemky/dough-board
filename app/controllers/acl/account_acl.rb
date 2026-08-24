module AccountACL

  # loan_terms is permitted key by key rather than wholesale: it's a json
  # column, and permitting the column would let a form post write arbitrary
  # JSON onto an account. Amortization::KEYS is what the calculation reads.
  def attributes
    [
      :name,
      :number,
      :institution_name,
      :positions_source,
      {loan_terms: Amortization::KEYS + ["debt_symbol"]}
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
