class OpenaiAnalysisService
  MAX_RETRIES = 10
  INITIAL_DELAY = 1

  def analyze_image(image_url, mobile_request = false, user = nil)
    prompt = generate_analysis_prompt(mobile_request, user)
    response = call_openai_api(prompt, image_url)
    parse_openai_response(response, mobile_request)
  end

  private

  def generate_analysis_prompt(mobile_request, user)
    base_prompt = <<~PROMPT
      First, analyze whether the image is a selfie or a food picture.
  
      If it's a selfie, please analyze this selfie image for skin conditions and provide a diagnosis:
      
      Analyze the skin carefully and provide recommendations that consider:
      - Current products the user is using: #{user.current_products.present? ? user.current_products : "None specified"}
      - Main skin concerns: #{user.skin_problem.present? ? user.skin_problem : "General skin health"}
      
      Provide your analysis in a clear, actionable format at a 5th grade reading level.
  
      If it's a food picture, analyze each item for antioxidants vs oxidants levels.
      The response should be returned in json format. Here's an example:
      "ingredients" => [ Congee with preserved vegetables: 40% oxidants, 60% antioxidants
          Scallion pancake: 70% oxidants, 30% antioxidants
          Fried dough stick (youtiao): 80% oxidants, 20% antioxidants ],
      "total" => [Total meal average: 63% oxidants, 37% antioxidants],
      "skin_health" => 4/10],
      "category" => "meal"
    PROMPT
  
    if mobile_request
      base_prompt += <<~MOBILE_PROMPT
  
      For selfie analysis, return response in JSON format with these exact keys:
      
      {
        "condition": {
          "primary_concerns": ["Acne (moderate)", "Dryness around cheeks"],
          "severity": "The acne appears moderate with some inflammatory lesions. Skin shows signs of dehydration.",
          "causes": ["Hormonal changes", "Over-cleansing", "Lack of moisturization"]
        },
        "products": [
          "CeraVe Foaming Facial Cleanser - gentle cleansing without over-drying",
          "The Ordinary Niacinamide 10% + Zinc 1% - reduces acne and oil production",
          "CeraVe Daily Moisturizing Lotion - lightweight hydration",
          "EltaMD UV Clear SPF 46 - non-comedogenic sun protection"
        ],
        "routine": {
          "morning": [
            "Step 1: Cleanse with CeraVe Foaming Facial Cleanser",
            "Step 2: Apply The Ordinary Niacinamide serum", 
            "Step 3: Moisturize with CeraVe Daily Moisturizing Lotion",
            "Step 4: Apply EltaMD UV Clear SPF 46"
          ],
          "evening": [
            "Step 1: Cleanse with CeraVe Foaming Facial Cleanser",
            "Step 2: Apply The Ordinary Niacinamide serum",
            "Step 3: Moisturize with CeraVe PM Facial Moisturizing Lotion"
          ]
        },
        "diet": [
          "Salmon - omega-3 fatty acids reduce inflammation and support skin barrier",
          "Spinach - vitamin A helps with skin cell turnover and acne healing",
          "Blueberries - antioxidants protect against free radical damage",
          "Green tea - anti-inflammatory properties help calm irritated skin",
          "Avoid dairy and high-glycemic foods which can trigger acne flare-ups"
        ],
        "category": "skin"
      }
      
      IMPORTANT INSTRUCTIONS:
        #{user.current_products.present? ? 
          "- The user currently uses: #{user.current_products}. Consider which of these products to keep, modify, or replace in your recommendations." : 
          "- The user hasn't specified current products, so provide a complete routine."
        }
        #{user.skin_problem.present? ? 
          "- Focus recommendations on addressing: #{user.skin_problem}" : 
          "- Provide general skin health recommendations."
        }
        - If current products are good, mention keeping them and suggest complementary products
        - If current products may be causing issues, suggest gentler alternatives
        - Tailor the routine complexity based on what they're already doing
        - Make dietary recommendations specific to their skin concerns
      MOBILE_PROMPT
    end

    base_prompt
  end

  def system_prompt
    "You are an expert dermatologist specializing in skin condition analysis from images. Provide a detailed diagnosis based on the provided selfie, including skin conditions, severity, potential causes, recommended treatments, and positive aspects of the skin."
  end

  def call_openai_api(prompt, image_url)
    client = OpenAI::Client.new
    retries = 0

    begin
      messages = [
        { "type": "text", "text": "#{system_prompt}\n\n#{prompt}" },
        { "type": "image_url", "image_url": { "url": image_url } }
      ]

      client.chat(
        parameters: {
          model: "gpt-4.1-mini",
          messages: [{ role: "user", content: messages }],
          max_tokens: 4096
        }
      )
    rescue Faraday::TooManyRequestsError => e
      retries += 1
      if retries <= MAX_RETRIES
        delay = INITIAL_DELAY * (2 ** (retries - 1))
        Rails.logger.info "OpenAI API rate limit hit, retrying in #{delay}s (attempt #{retries}/#{MAX_RETRIES})"
        sleep(delay)
        retry
      else
        Rails.logger.error "OpenAI API max retries (#{MAX_RETRIES}) reached: #{e.message}"
        raise e
      end
    rescue StandardError => e
      Rails.logger.error "OpenAI API error: #{e.message}"
      raise e
    end
  end

  def download_image(image_url)
    URI.open(image_url, read_timeout: 10).read
  rescue OpenURI::HTTPError => e
    raise "Failed to download image from #{image_url}: #{e.message}"
  rescue Errno::ETIMEDOUT, Net::ReadTimeout => e
    raise "Timeout downloading image from #{image_url}: #{e.message}"
  end

  def parse_openai_response(response, json_requested = false)
    content = response.dig("choices", 0, "message", "content")
    
    if json_requested && content
      # Try to extract and parse JSON if it's wrapped in markdown code blocks
      if content.include?('```json')
        json_match = content.match(/```json\s*(\{.*?\})\s*```/m)
        if json_match
          begin
            parsed_content = JSON.parse(json_match[1])
          rescue JSON::ParserError => e
            Rails.logger.error "Failed to parse JSON from OpenAI response: #{e.message}"
            parsed_content = content # Fall back to raw content
          end
        else
          parsed_content = content
        end
      else
        # Try to parse as direct JSON
        begin
          parsed_content = JSON.parse(content)
        rescue JSON::ParserError
          parsed_content = content
        end
      end
    else
      parsed_content = content
    end

    {
      diagnosis: parsed_content,
      timestamp: Time.current,
      model_info: {
        name: response["model"],
        usage: {
          prompt_tokens: response.dig("usage", "prompt_tokens"),
          completion_tokens: response.dig("usage", "completion_tokens"),
          total_tokens: response.dig("usage", "total_tokens")
        }
      }
    }
  end
end