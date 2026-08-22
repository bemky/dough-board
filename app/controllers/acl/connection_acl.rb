module ConnectionACL

  # Everything else about a connection is the provider's to say — the
  # institution, whether it's disabled, when it last synced. Discovery writes
  # those; a form never should.
  def attributes
    [
      :connector,
      :foreign_id,
      :name
    ]
  end

  def nested
    [
    ]
  end

  def orders
    [
      :connector,
      :financial_institution,
      :synced_at
    ]
  end

  def includes
    {accounts: true}
  end

end
