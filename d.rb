require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'json'
require 'set'

Capybara.register_driver :chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :chrome
Capybara.default_max_wait_time = 10



class DohaBookFairScraper
  include Capybara::DSL

  def start
    visit 'https://www.dohabookfair.qa/الزوار/ابحث-عن-كتاب/'

    # Fetch all category values first (value + name)
categories = []
visit 'https://www.dohabookfair.qa/الزوار/ابحث-عن-كتاب/'
select = find('select#strSubject', visible: false)
select.all('option').each do |o|
  next if o.text.include?('اختر')
  categories << [o.text.strip, o[:value]]
end
puts "to"
categories.each do |category_name, category_value|

      #category_name = opt.text.strip
      #category_value = opt[:value]
      filename = "#{category_name.gsub(/[^\p{Arabic}\w\s\-]/, '').gsub(/\s+/, '_')}.json"

      puts "==> Scraping category: #{category_name}"

      # Reset page, state and visited titles
      visit 'https://www.dohabookfair.qa/الزوار/ابحث-عن-كتاب/'
      sleep 2

      execute_script(<<~JS, category_value)
        var select = document.getElementById('strSubject');
        select.value = arguments[0];
        var event = new Event('change', { bubbles: true });
        select.dispatchEvent(event);
      JS

      sleep 1
      find('button#btnSearch').click
      sleep 3

      begin
        find('select#maxRows').select('500')
        sleep 2
      rescue
        puts "⚠️ Could not set 500 rows for #{category_name}"
        next
      end

      all_data = []
      seen_titles = Set.new
      loop do
        begin
          rows = all('#BookList_Result.table tbody tr')
          break if rows.empty?

          data = rows.map do |tr|
            values = tr.all('td').map { |td| td.text.strip }
            {
              title:     values[1],
              category:  values[2],
              author:    values[3],
              year:      values[4],
              publisher: values[5],
              country:   values[6],
              price:     values[7],
              hall:      values[8]
            }
          end

          new_data = data.reject { |row| seen_titles.include?(row[:title]) }

          break if new_data.empty? # nothing new = we reached the end

          new_data.each { |row| seen_titles << row[:title] }
          all_data.concat(new_data)

          puts "🔹 Fetched #{new_data.size} new books (total: #{seen_titles.size})"

          # Go to next page
          links = all('a.page-link', minimum: 1)
          next_link = links.last
          break if next_link[:class]&.include?('disabled')
          next_link.click
          sleep 2
        rescue => e
          puts "⚠️ Pagination failed: #{e.message}"
          break
        end
      end

      File.write(filename, JSON.pretty_generate(all_data))
      puts "✅ Saved #{all_data.size} unique books to #{filename}"
    rescue => e
      puts "❌ Error scraping category #{category_name}: #{e.message}"
    end
  end
end


DohaBookFairScraper.new.start