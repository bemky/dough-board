require 'uri'
require 'net/http'
require 'nokogiri'

class SplitHistoryScraper
  include Singleton
  
  def splits(symbol)
    url = URI("https://www.splithistory.com/#{symbol.downcase}/")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    response = http.request(Net::HTTP::Get.new(url))
    doc = Nokogiri::HTML(response.body)
    
    if table = doc.css('table').find{|x| x.content.lstrip.starts_with? "#{symbol.upcase} Split History Table"}
      # The table carries two header rows (a title row and a "Date | Ratio"
      # column-header row), so skip any row whose first cell isn't a real date
      # rather than blowing up on it.
      table.css('tr').filter_map{|row|
        date = begin
          DateTime.strptime(row.children[0].content, "%m/%d/%Y")
        rescue Date::Error
          nil
        end
        next unless date

        ratio_parts = row.children[1].content.split(" for ").map(&:to_f)
        next if ratio_parts.length < 2 || ratio_parts[1].zero?

        [date, ratio_parts[0] / ratio_parts[1]]
      }
    else
      []
    end
  end

  # Delegates all uncauge class method calls to the singleton
  def self.method_missing(method, *args, &block)
    instance.__send__(method, *args, &block)
  end
end
