require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'
require 'parallel'

# Capybara Configuration
Capybara.default_driver = :selenium_headless
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1920,1080')
  Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
end
Capybara.default_max_wait_time = 10

class BookScraper
  include Capybara::DSL

  def initialize(output_prefix)
    @mechanize = Mechanize.new
    @csv_file = "#{output_prefix}-books.csv"
    @json_file = "#{output_prefix}-books.json"

    # Ensure output files exist
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
    session = Capybara::Session.new(:selenium_headless)  # New session per thread
    session.visit(genre_url)

    loop do
      current_page_url = session.current_url

      session.all('.gridview .imggrid a').each do |book_link|
        book_url = book_link['href']
        puts "Processing book: #{book_url} (Page URL: #{current_page_url})"

        begin
          book_page = @mechanize.get(book_url)
        rescue StandardError => e
          puts "Error accessing book URL #{book_url}: #{e.message}"
          next
        end

        title = book_page.at('div.p-title')&.text&.strip
        author = book_page.at('div.p-author')&.text&.strip&.gsub(/^لـ /, '')
        image_url = book_page.at('.p-cover img')&.[]('src')
        year = book_page.at('.p-info b:contains("تاريخ النشر")')&.text&.split(':')&.last&.strip
        publisher = book_page.at('.p-info b:contains("الناشر")')&.next&.text&.strip
        isbn = book_page.at('.p-info b:contains("ردمك")')&.next&.text&.strip
        summary = book_page.at('span.desc.nabza d')&.next&.text&.strip
        local_price = extract_price(book_page)
        rate = 0.33
        usd_price = (local_price * rate).to_i if local_price

        @csv << [title, author, genre, book_url, image_url, year, publisher, isbn, summary, usd_price, current_page_url]
        @json << { title: title, author: author, genre: genre, book_url: book_url, image: image_url, year: year,
                   publisher: publisher, summary: summary, isbn: isbn, price_in_usd: usd_price, page_url: current_page_url }
        File.open(@json_file, 'a') { |f| f.write(JSON.generate(@json.last) + "\n") }
      end

      next_button = begin
        session.first('img[src$="arrowr.png"]', visible: true)
      rescue StandardError
        nil
      end
      break if next_button.nil?

      next_button.click
      sleep 5
    end
  end
end

# Get input file from command line argument (or default to 'links.txt')
input_file = ARGV[0] || 'links.txt'
output_prefix = File.basename(input_file, '.txt')  # Generate output filenames based on input file

# Read links from the specified input file
links = File.readlines(input_file).map(&:strip).map { |line| line.split(' ', 2) }.reject { |entry| entry.any?(&:nil?) }

# Run with parallel processing (2 threads per job)
Parallel.each(links, in_threads: 2) do |(category_url, genre)|
  scraper = BookScraper.new(output_prefix)
  scraper.scrape_books(category_url, genre)
end
