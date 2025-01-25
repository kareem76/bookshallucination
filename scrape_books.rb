require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'

# Capybara configuration
Capybara.default_driver = :selenium_headless # Use headless Firefox
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless') # Run Firefox in headless mode
  options.add_argument('--disable-gpu') # Disable GPU for compatibility
  options.add_argument('--window-size=1920,1080') # Set window size
  Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
end
Capybara.default_max_wait_time = 10

# Scraper class
class BookScraper
  include Capybara::DSL

  def initialize
    @mechanize = Mechanize.new
    @csv_file = '7adith.csv'
    @json_file = '7adith.json'
    @last_page_file = 'last_page.txt'

    # Create files if they don't exist
    FileUtils.touch(@csv_file) unless File.exist?(@csv_file)
    FileUtils.touch(@json_file) unless File.exist?(@json_file)
    FileUtils.touch(@last_page_file) unless File.exist?(@last_page_file)

    @last_page_url = begin
      File.read(@last_page_file).strip
    rescue StandardError
      nil
    end
    @csv = CSV.open(@csv_file, 'a',
                    headers: ['Title', 'Author', 'Genre', 'Book URL', 'Image', 'Year', 'Publisher', 'ISBN', 'Price (USD)', 'Page URL'])
    @json = []
  end

  def extract_price(book_page)
    price_text = book_page.at('b.ourprice')&.text&.strip
    return nil unless price_text

    begin
      price_text.split(' ').first.to_f
    rescue StandardError
      nil
    end
  end

  def convert_to_usd(local_price, rate)
    return nil if local_price.nil? || rate.nil? || local_price <= 0 || rate <= 0

    (local_price * rate).to_i
  end

  def scrape_books(genre_url, genre, _last_page_url = nil)
    puts "Scraping books for genre: #{genre}"

    # Start from the last page URL or the base genre URL
    start_url = @last_page_url.empty? ? genre_url : @last_page_url
    #visit(start_url)
     #start_url = @last_page_file.nil? || @last_page_file.empty? ? genre_url : @last_page_file
     visit(genre_url)
     #visit(start_url)

    loop do
      # Record the current page URL for resuming
      current_page_url = page.current_url
      File.write(@last_page_file, current_page_url)

      # Process all books on the current page
      all('.gridview .imggrid a').each do |book_link|
        book_url = book_link['href']
        puts "Processing book: #{book_url} (Page URL: #{current_page_url})"

        # Fetch book page
        begin
          book_page = @mechanize.get(book_url)
        rescue Mechanize::ResponseCodeError => e
          puts "Error accessing book URL #{book_url}: #{e.message}"
          next
        end

        # Fetch book details
        title = book_page.at('div.p-title')&.text&.strip
        author = book_page.at('div.p-author')&.text&.strip&.gsub(/^لـ /, '')
        summary = book_page.at('meta[property="og:description"]')&.[]('content')&.strip
        image_url = book_page.at('.p-cover img')&.[]('src')
        year = book_page.at('.p-info b:contains("تاريخ النشر")')&.text&.split(':')&.last&.strip
        publisher = book_page.at('.p-info b:contains("الناشر")')&.next&.text&.strip
        isbn = book_page.at('.p-info b:contains("ردمك")')&.next&.text&.strip

        # Extract price and convert to USD
        local_price = extract_price(book_page)
        rate = 0.33 # Example rate
        usd_price = convert_to_usd(local_price, rate)

        # Save to CSV
        @csv << [title, author, genre, book_url, image_url, year, publisher, isbn, usd_price, current_page_url]

        # Save to JSON
        @json << { title: title, author: author, genre: genre, book_url: book_url, image: image_url, year: year,
                   publisher: publisher, isbn: isbn, price_in_usd: usd_price, page_url: current_page_url }
        File.open(@json_file, 'a') { |f| f.write(JSON.generate(@json.last) + "\n") }
      end

      # Check for "next page" button
      next_button = begin
        first('img[src$="arrowr.png"]', visible: true)
      rescue StandardError
        nil
      end
      if next_button.nil?
        puts "No 'next page' button found. Moving to the next genre."
        break # Exit the loop and move to the next genre
      end

      next_button.click
      sleep 5 # Wait for the next page to load
    end
  end
end

# Main execution
puts "Reading links from 'links.txt'..."
File.readlines('links.txt').each_with_index do |line, index|
  category_url, genre = line.strip.split(' ', 2)

  if category_url.nil? || genre.nil?
    puts "Skipping invalid line ##{index + 1}: #{line.inspect}"
    next
  end

  scraper = BookScraper.new
  scraper.scrape_books(category_url, genre)
end

puts 'Scraping completed!'

