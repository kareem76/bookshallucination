require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'

# Capybara Configuration for Chrome
Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1920,1080')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :selenium_chrome_headless
Capybara.default_max_wait_time = 10

class BookScraper
  include Capybara::DSL

  def initialize(output_prefix)
    @mechanize = Mechanize.new
    @csv_file = "#{output_prefix}-books.csv"
    @json_file = "#{output_prefix}-books.json"

    FileUtils.touch(@csv_file) unless File.exist?(@csv_file)
    FileUtils.touch(@json_file) unless File.exist?(@json_file)

    @csv = CSV.open(@csv_file, 'a', headers: ['Title', 'Author', 'Genre', 'Book URL', 'Image', 'Year', 'Publisher', 'summary', 'ISBN', 'Price (USD)', 'Page URL'])
    @json = []
  end

  def extract_price(book_page)
    price_text = book_page.at('b.ourprice')&.text&.strip
    return nil unless price_text
    price_text.split(' ').first.to_f rescue nil
  end

  def scrape_books(genre_url, genre)
    puts "Scraping books for genre: #{genre}"
    session = Capybara::Session.new(:selenium_chrome_headless)
    
    begin
      session.visit(genre_url)
      sleep 3  # Wait for JS and layout

      loop do
        current_page_url = session.current_url

        session.all('.gridview .imggrid a').each do |book_link|
          book_url = book_link['href']
          puts "Processing book: #{book_url} (Page URL: #{current_page_url})"

          sleep 0.5  # Delay before each book request

          begin
            book_page = @mechanize.get(book_url)
          rescue StandardError => e
            puts "Error accessing book URL #{book_url}: #{e.message}"
            next
          end

          title = book_page.at('div.p-title')&.text&.strip
          author = book_page.at('div.p-author')&.text&.strip&.gsub(/^لـ /, '')
          image_url = book_page.at('.p-cover img')&.[]('src')
          year = book_page.at('.p-info b:contains("تاريخ النشر")')&.next&.text&.strip
          publisher = book_page.at('.p-info b:contains("الناشر")')&.next&.text&.strip
          isbn = book_page.at('.p-info b:contains("ردمك")')&.next&.text&.strip

          # Extract and clean summary
          d_content = book_page.at('span.desc.nabza d')
          if d_content
            d_content.search('span').each(&:remove)
            summary = d_content.text.strip
            summary = "null" if summary.empty?
          else
            summary = "null"
          end

          local_price = extract_price(book_page)
          usd_price = (local_price * 0.33).to_i if local_price

          @csv << [title, author, genre, book_url, image_url, year, publisher, isbn, summary, usd_price, current_page_url]
          @json << {
            title: title, author: author, genre: genre, book_url: book_url,
            image: image_url, year: year, publisher: publisher, summary: summary,
            isbn: isbn, price_in_usd: usd_price, page_url: current_page_url
          }
          File.open(@json_file, 'a') { |f| f.write(JSON.generate(@json.last) + "\n") }
        end

        next_button = session.first('img[src$="arrowr.png"]', visible: true)
        break unless next_button

        next_button.click
        sleep 5  # Delay to allow next page to load
      end
    ensure
      session.driver.quit rescue nil
    end
  end
end

# === Script Entry ===

input_file = ARGV[0] || 'links.txt'
output_prefix = File.basename(input_file, '.txt')
links = File.readlines(input_file).map(&:strip).map { |line| line.split(' ', 2) }.reject { |entry| entry.any?(&:nil?) }

# No parallel to avoid memory crash
links.each do |(category_url, genre)|
  scraper = BookScraper.new(output_prefix)
  scraper.scrape_books(category_url, genre)
end
