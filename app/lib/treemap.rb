# Squarified treemap layout (Bruls, Huizing & van Wijk, 2000).
#
# Packs weighted items into a rectangle, greedily building rows along whichever
# side is currently shorter and closing a row as soon as adding the next item
# would make its tiles less square. Used to render a portfolio as proportional
# boxes rather than a single stacked bar.
class Treemap

  Tile = Struct.new(:item, :x, :y, :width, :height, keyword_init: true)

  # Yields each item to get its weight; items with a non-positive weight are
  # dropped. Returns Tiles laid out in a `width` x `height` box (percentages by
  # default, so they can be dropped straight into CSS), largest first.
  def self.layout(items, width: 100.0, height: 100.0, &weight)
    new(items, width, height, &weight).tiles
  end

  def initialize(items, width, height, &weight)
    @width = width.to_f
    @height = height.to_f
    @items = items.map { |item| [item, weight.call(item).to_f] }
                  .select { |_, value| value > 0 }
                  .sort_by { |_, value| -value }
  end

  def tiles
    return [] if @items.empty?

    # Scale weights into areas so the items exactly fill the box.
    scale = (@width * @height) / @items.sum(&:last)
    queue = @items.map { |item, value| [item, value * scale] }

    @tiles = []
    @x, @y, @w, @h = 0.0, 0.0, @width, @height
    row = []

    until queue.empty?
      candidate = row.map(&:last) + [queue.first.last]
      if row.empty? || worst(row.map(&:last)) >= worst(candidate)
        row << queue.shift
      else
        place(row)
        row = []
      end
    end
    place(row) unless row.empty?

    @tiles
  end

  private

  # Aspect ratio of the least-square tile in a row, the value squarify minimizes.
  def worst(areas)
    side = [@w, @h].min
    total = areas.sum
    return Float::INFINITY if total.zero? || side.zero?
    [(side**2 * areas.max) / total**2, total**2 / (side**2 * areas.min)].max
  end

  # Lay the row out as a band along the shorter side, then shrink the remaining
  # box by the band's thickness.
  def place(row)
    total = row.sum(&:last)

    if @w <= @h
      thickness = total / @w
      offset = @x
      row.each do |item, area|
        length = area / thickness
        @tiles << Tile.new(item: item, x: offset, y: @y, width: length, height: thickness)
        offset += length
      end
      @y += thickness
      @h -= thickness
    else
      thickness = total / @h
      offset = @y
      row.each do |item, area|
        length = area / thickness
        @tiles << Tile.new(item: item, x: @x, y: offset, width: thickness, height: length)
        offset += length
      end
      @x += thickness
      @w -= thickness
    end
  end

end
