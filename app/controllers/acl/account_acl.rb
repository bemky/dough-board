module AccountACL

  def attributes
    [
      :name,
      :number,
      :institution_name,
      :positions_source
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
