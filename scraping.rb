require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'

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
    @results = []  # Store scraped data before writing

    # Ensure output files exist
    FileUtils.touch(@csv_file) unless File.exist?(@csv_file)
    FileUtils.touch(@json_file) unless File.exist?(@json_file)

    @csv = CSV.open(@csv_file, 'a', write_headers: true, headers: ['Title', 'Author', 'Genre', 'Book URL', 'Image', 'Year', 'Publisher', 'ISBN', 'Price (USD)', 'Summary', 'Page URL'])
  end

  def extract_price(book_page)
    price_text = book_page.at('b.ourprice')&.text&.strip
    return nil unless price_text
    price_text.split(' ').first.to_f rescue nil
  end

  def extract_summary(book_page)
    summary_element = book_page.at('span.desc.nabza d')
    summary_element ? summary_element.text.strip : nil
  end

  def scrape_books(genre_url, genre, start_page, end_page)
    puts "Scraping books for genre: #{genre}, Pages: #{start_page} - #{end_page}"

   (start_page..end_page).each do |page_number|
      page_url = "#{genre_url}&Page=#{page_number}"
      puts "Visiting page: #{page_url}"

      session = Capybara::Session.new(:selenium_headless)
      session.visit(page_url)

      session.all('.gridview .imggrid a').each do |book_link|
        book_url = book_link['href']
        puts "Processing book: #{book_url} (Page URL: #{page_url})"

        begin
          book_page = @mechanize.get(book_url)
          title = book_page.at('div.p-title')&.text&.strip
          author = book_page.at('div.p-author')&.text&.strip&.gsub(/^لـ /, '')
          image_url = book_page.at('.p-cover img')&.[]('src')
          year = book_page.at('.p-info b:contains("تاريخ النشر")')&.next&.text&.strip
          publisher = book_page.at('.p-info b:contains("الناشر")')&.next&.text&.strip
          isbn = book_page.at('.p-info b:contains("ردمك")')&.next&.text&.strip
          local_price = extract_price(book_page)
          rate = 0.33
          usd_price = (local_price * rate).to_i if local_price
          summary = extract_summary(book_page)

          @results << { title: title, author: author, genre: genre, book_url: book_url, image: image_url, 
                        year: year, publisher: publisher, isbn: isbn, price_in_usd: usd_price, summary: summary, page_url: page_url }
        rescue StandardError => e
          puts "Error accessing book URL #{book_url}: #{e.message}"
          next
        end
      end

      sleep 2  # Reduced sleep time between page requests
    end

    # Write results to files in batch
    write_results
  end

  def write_results
    @results.each { |row| @csv << row.values }
    File.open(@json_file, 'a') do |f|
      @results.each { |result| f.write(JSON.generate(result) + "\n") }
    end
  end
end

# Define the base URL and genre
base_url = "https://www.neelwafurat.com/browse1.aspx?ddmsubject=10&subcat=01&search=books"
genre = "Books"

# Create an instance of BookScraper and start scraping
#scraper = BookScraper.new("output")
#scraper.scrape_books(base_url, genre)
# Parse arguments from GitHub Actions
start_page = ARGV[0].to_i
end_page = ARGV[1].to_i

scraper = BookScraper.new("output")
scraper.scrape_books("https://www.neelwafurat.com/browse1.aspx?ddmsubject=10&subcat=01&search=books", "Books", start_page, end_page)


