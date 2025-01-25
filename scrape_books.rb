require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'

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

class BookScraper
  include Capybara::DSL

  def initialize
    @mechanize = Mechanize.new
    @csv_file = "books_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
    @json_file = "books_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    FileUtils.touch(@csv_file)
    FileUtils.touch(@json_file)
    @csv = CSV.open(@csv_file, 'a', headers: true)
  end

  def scrape_books(genre_url, genre)
    puts "Scraping books for genre: #{genre}"
    visit(genre_url)

    pages_scraped = 0
    max_pages = 50 # Prevent infinite loops

    until pages_scraped >= max_pages
      all('.gridview .imggrid a').each do |book_link|
        process_book(book_link['href'], genre, genre_url)
      rescue StandardError => e
        puts "Error processing book link: #{e.message}"
        next
      end

      next_button = first('img[src$="arrowr.png"]', visible: true, minimum: 1) rescue nil
      break unless next_button

      next_button.click
      sleep 5
      pages_scraped += 1
    end
  end

  def process_book(book_url, genre, genre_url)
    book_page = @mechanize.get(book_url) rescue nil
    return unless book_page

    title = book_page.at('div.p-title')&.text&.strip
    author = book_page.at('div.p-author')&.text&.strip&.gsub(/^لـ /, '')
    image_url = book_page.at('.p-cover img')&.[]('src')
    year = book_page.at('.p-info b:contains("تاريخ النشر")')&.next&.text&.strip
    publisher = book_page.at('.p-info b:contains("الناشر")')&.next&.text&.strip
    isbn = book_page.at('.p-info b:contains("ردمك")')&.next&.text&.strip

    local_price = extract_price(book_page)
    rate = 0.33
    usd_price = (local_price * rate).to_i rescue nil

    save_to_csv([title, author, genre, book_url, image_url, year, publisher, isbn, usd_price, genre_url])
    save_to_json(title, author, genre, book_url, image_url, year, publisher, isbn, usd_price, genre_url)
  end

  def extract_price(book_page)
    book_page.at('b.ourprice')&.text&.to_f rescue nil
  end

  def save_to_csv(data)
    @csv << data
  end

  def save_to_json(title, author, genre, book_url, image_url, year, publisher, isbn, usd_price, genre_url)
    json_data = {
      title: title, author: author, genre: genre, book_url: book_url, image: image_url,
      year: year, publisher: publisher, isbn: isbn, price_in_usd: usd_price, page_url: genre_url
    }
    File.open(@json_file, 'a') { |f| f.flock(File::LOCK_EX); f.write(JSON.generate(json_data) + "\n") }
  end
end

File.readlines('links.txt').each_with_index do |line, index|
  category_url, genre = line.strip.split(' ', 2)
  next unless category_url && genre

  scraper = BookScraper.new
  scraper.scrape_books(category_url, genre)
end
