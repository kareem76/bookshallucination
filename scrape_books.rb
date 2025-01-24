require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'json'
require 'fileutils'
require 'time'

# Capybara configuration
Capybara.default_driver = :selenium_headless
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1920,1080')
  Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
end
Capybara.default_max_wait_time = 10

# Scraper class
class BookScraper
  include Capybara::DSL

  def initialize
    @mechanize = Mechanize.new
    @output_dir = 'scraped_books'
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)
    @last_page_file = 'last_page.txt'
    @current_interval_file = generate_file_name
    @data_buffer = []
    @start_time = Time.now
  end

  def generate_file_name
    timestamp = Time.now.strftime('%Y%m%d_%H%M')
    File.join(@output_dir, "books_#{timestamp}.json")
  end

  def save_to_file
    File.open(@current_interval_file, 'w') do |file|
      file.write(JSON.pretty_generate(@data_buffer))
    end
    puts "Data saved to #{@current_interval_file}"
    @data_buffer.clear
  end

  def upload_artifacts
    puts "Uploading artifacts..."
    system("tar -czf artifacts.tar.gz #{@output_dir}") # Compress the folder
    system("echo '::set-output name=artifact_path::artifacts.tar.gz'") # GitHub Actions artifact output
  end

  def scrape_books(genre_url, genre, _last_page_url = nil)
  puts "Scraping books for genre: #{genre}"

  # Start from the genre URL
  visit(genre_url)

  # Process books on the current page
  all('.gridview .imggrid a').each do |book_link|
    book_url = book_link['href']
    puts "Processing book: #{book_url} (Genre: #{genre})"

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
    @csv << [title, author, genre, book_url, image_url, year, publisher, isbn, usd_price, genre_url]

    # Save to JSON
    @json << { title: title, author: author, genre: genre, book_url: book_url, image: image_url, year: year,
               publisher: publisher, isbn: isbn, price_in_usd: usd_price, page_url: genre_url }
    File.open(@json_file, 'a') { |f| f.write(JSON.generate(@json.last) + "\n") }
  end

  # Check for the "next page" button
  next_button = begin
    first('img[src$="arrowr.png"]', visible: true)
  rescue StandardError
    nil
  end
  
  if next_button.nil?
    puts "No 'next page' button found. Moving to the next genre."
    return true # Proceed to the next category URL
  end

  # If a "next page" button exists, click and wait
  next_button.click
  sleep 5 # Wait for the next page to load
  return false # Continue scraping the current genre's next page
end


    save_to_file unless @data_buffer.empty? # Save any remaining data
  end
end

# Main execution
scraper = BookScraper.new
puts "Reading links from 'links.txt'..."
File.readlines('links.txt').each_with_index do |line, index|
  category_url, genre = line.strip.split(' ', 2)
  next if category_url.nil? || genre.nil?

  scraper.scrape_books(category_url, genre)
end
puts 'Scraping completed!'
