require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'
require 'fileutils'
require 'set'

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
    @results = []  
    @unique_book_urls = Set.new  

    # Ensure output files exist
    FileUtils.touch(@csv_file) unless File.exist?(@csv_file)
    FileUtils.touch(@json_file) unless File.exist?(@json_file)

    @csv = CSV.open(@csv_file, 'a', write_headers: true, headers: ['Title', 'Author', 'Genre', 'Book URL', 'Image', 'Year', 'Publisher', 'ISBN', 'Price (USD)', 'Summary', 'Page URL'])

    # **Initialize Capybara session once**
    @session = Capybara::Session.new(:selenium_headless)
  end

  def extract_price(book_page)
    price_text = book_page.at('b.ourprice')&.text&.strip
    return nil unless price_text
    price_text.split(' ').first.to_f rescue nil
  end

  def scrape_books(genre_url, genre, start_page, end_page)
    #puts "🔵 Scraping books for genre: #{genre}, Pages: #{start_page} - #{end_page}"

    (start_page..end_page).each do |page_number|
      page_url = "#{genre_url}&Page=#{page_number}"
      #puts "🟡 Visiting page: #{page_url}"

      # ✅ VISIT PAGE ONCE ONLY
      @session.visit(page_url)
      sleep 2  # Prevents excessive requests

      book_links = @session.all('.gridview .imggrid a').map { |link| link['href'] }.uniq  # ✅ Ensure unique links
      #puts "🔹 Found #{book_links.size} book links on page #{page_number}"

      book_links.each do |book_url|
        next if @unique_book_urls.include?(book_url)  # ✅ Skip duplicates

        #puts "🟢 Processing book: #{book_url} (Page URL: #{page_url})"

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

          # **Extract Summary**
         d_content = book_page.at('span.desc.nabza d')

if d_content
  # Remove all <span> tags from the <d> content
  d_content.search('span').each(&:remove)

  # Get the cleaned text from the <d> tag
  summary = d_content.text.strip

  # Check if the summary is empty
  if summary.empty?
    summary = "null"
  end
else
  summary = "null"
end
          @unique_book_urls.add(book_url)  # ✅ Add to unique list
          @results << { title: title, author: author, genre: genre, book_url: book_url, image: image_url,
                        year: year, publisher: publisher, isbn: isbn, price_in_usd: usd_price, summary: summary, page_url: page_url }

        rescue StandardError => e
          #puts "❌ Error accessing book URL #{book_url}: #{e.message}"
          next
        end
      end
    end

    puts JSON.pretty_generate(@results)
    write_results  
  end

  def write_results
    #puts "💾 Writing results to files..."
    @results.each { |row| @csv << row.values }
    File.open(@json_file, 'a') do |f|
      @results.each { |result| f.write(JSON.generate(result) + "\n") }
    end
  end
end

# Parse arguments from GitHub Actions
start_page = ARGV[0].to_i
end_page = ARGV[1].to_i

puts "🚀 Starting BookScraper from Page #{start_page} to #{end_page}"
scraper = BookScraper.new("output")
scraper.scrape_books("https://www.neelwafurat.com/browsel1.aspx?cat=10&subcat=02&search=books", "شعر", start_page, end_page)
puts "✅ Scraping completed!"
