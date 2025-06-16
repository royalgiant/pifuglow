# app/services/yesstyle_product_sitemap_parser.rb
require 'open-uri'
require 'nokogiri'
require 'uri'

class YesstyleProductSitemapParser
  SITEMAP_URL = 'https://www.yesstyle.com/en/product-sitemap'
  
  # Define the skincare categories we want to scrape (from Face Serums to Sun care)
  SKINCARE_CATEGORIES = [
    'Face Serums',
    'Moisturizers',
    'Face Cleansers',
    'Toners',
    'Exfoliators',
    'Face Masks',
    'Eye Care',
    'Acne Treatments',
    'Lip Care',
    'Sun Care'
  ].freeze

  def self.process
    puts "Starting sitemap processing..."
    
    # Fetch and parse the HTML sitemap page
    html = URI.open(SITEMAP_URL).read
    doc = Nokogiri::HTML(html)

    # Find the Skin Care section
    skincare_section = find_skincare_section(doc)
    return unless skincare_section

    puts "Found Skin Care section, processing categories..."

    # Process each skincare category
    SKINCARE_CATEGORIES.each do |category_name|
      puts "Processing category: #{category_name}"
      process_category(skincare_section, category_name)
    end

    puts "Sitemap processing completed!"
  rescue StandardError => e
    Rails.logger.error "Sitemap parsing failed: #{e.message}"
    puts "Error: #{e.message}"
  end

  private

  def self.find_skincare_section(doc)
    # Look for the "Skin Care" h2 element and get its parent container
    skincare_header = doc.xpath("//h2[text()='Skin Care']").first
    
    if skincare_header
      # Get the parent div that contains all the skincare categories
      skincare_section = skincare_header.parent
      puts "Found Skin Care section"
      return skincare_section
    end

    puts "Warning: Could not find Skin Care section"
    nil
  end

  def self.process_category(skincare_section, category_name)
    # Find the specific category h3 element
    category_header = skincare_section.xpath(".//h3[text()='#{category_name}']").first
    
    unless category_header
      puts "Category '#{category_name}' not found"
      return
    end

    # Get the next sibling div that contains the product links
    products_container = category_header.next_element
    
    unless products_container
      puts "No products container found for #{category_name}"
      return
    end

    # Find all product links (a tags) within this category
    product_links = products_container.css('a')
    
    if product_links.empty?
      puts "No product links found for category: #{category_name}"
      return
    end

    puts "Found #{product_links.length} products in #{category_name}"

    product_links.each_with_index do |link, index|
      begin
        url = normalize_url(link['href'])
        title = link.text.strip
        
        next if title.empty? || url.nil?
        
        puts "Processing product #{index + 1}/#{product_links.length}: #{title}"
        
        # Fetch product cover image
        cover_image = fetch_product_images(url)

        # Save to database
        Product.find_or_create_by(url: url) do |p|
          p.title = title
          p.category = category_name
          p.images = cover_image
        end

        # Add a small delay to be respectful to the server
        sleep(0.5)
        
      rescue StandardError => e
        puts "Error processing product: #{e.message}"
        Rails.logger.error "Failed to process product #{url}: #{e.message}"
      end
    end
  end

  def self.normalize_url(url)
    return nil unless url
    
    if url.start_with?('/')
      "https://www.yesstyle.com#{url}"
    elsif url.start_with?('http')
      url
    else
      "https://www.yesstyle.com/#{url}"
    end
  end

  def self.fetch_product_images(url)
    return nil unless url

    begin
      puts "  - Fetching cover image from: #{url}"
      
      # Add headers to mimic a real browser request
      headers = {
        'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      }
      
      doc = Nokogiri::HTML(URI.open(url, headers))
      
      # Based on the DOM structure, look for the main product image
      # Try specific selectors for the cover image
      cover_image_selectors = [
        '.productDetailPage_productImageCover__chqZe img',  # Main cover image from DOM
        '.productDetailPage_coverImageWrapper img',          # Cover wrapper
        '.main-product-image img',                           # Generic main image
        '.product-image-main img',                           # Main product image
        'img[loading="eager"]'                               # First loaded image
      ]
      
      cover_image_selectors.each do |selector|
        img = doc.css(selector).first
        next unless img
        
        # Get the image source
        src = img['src'] || img['data-src']
        next unless src
        
        # Normalize the URL
        normalized_url = case src
        when /^\/\//
          "https:#{src}"
        when /^\//
          "https://www.yesstyle.com#{src}"
        when /^http/
          src
        else
          "https://www.yesstyle.com/#{src}"
        end
        
        puts "  - Found cover image"
        return normalized_url
      end
      
      puts "  - No cover image found"
      nil
      
    rescue OpenURI::HTTPError => e
      puts "  - HTTP Error fetching image: #{e.message}"
      nil
    rescue StandardError => e
      puts "  - Error fetching image: #{e.message}"
      Rails.logger.error "Failed to fetch image for #{url}: #{e.message}"
      nil
    end
  end
end

# Usage:
# SitemapParser.process