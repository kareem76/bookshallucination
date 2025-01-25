name: Scrape Books

on:
  workflow_dispatch:

jobs:
  scrape:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout Repository
      uses: actions/checkout@v4

    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.1
        bundler-cache: true

    - name: Install Dependencies
      run: |
        gem install bundler
        bundle install

    - name: Start Scraper
      run: |
        # Define the output file name with timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
        json_file="books_${timestamp}.json"
        
        # Run the scraper script and pass the output file as a parameter
        echo "Running the Ruby script..."
        bundle exec ruby scrape_books.rb --output $json_file  # Run with bundle exec
        
        # Check if the JSON file is generated, then upload it
        if [ -f "$json_file" ]; then
          echo "JSON file $json_file created. Uploading..."
          gh run upload-artifact --name "books_${timestamp}" --path "$json_file"
        else
          echo "Error: JSON file $json_file was not created."
        fi
