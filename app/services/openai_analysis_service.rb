class OpenaiAnalysisService
  MAX_RETRIES = 10
  INITIAL_DELAY = 1

  def analyze_image(image_url, mobile_request = false, user = nil, subscribed = false, previous_analysis = nil)
    prompt = generate_analysis_prompt(mobile_request, user, subscribed, previous_analysis)
    response = call_openai_api(prompt, image_url)
    parse_openai_response(response, mobile_request)
  end

  private

  def generate_analysis_prompt(mobile_request, user, subscribed, previous_analysis = nil)
    base_prompt = <<~PROMPT
      Analyze this selfie image for skin conditions and provide a diagnosis:
      1. Identify any visible skin conditions (e.g., acne, dryness, redness, hyperpigmentation).
      2. Describe the severity of each condition (mild, moderate, severe). The format should always be something like "Acne (mild to moderate)" in one line.
      3. Suggest potential causes (e.g., environmental factors, diet, skincare routine).
      4. Provide specific products & brands (e.g CeraVe Moisturizing Cream, CeraVe PM Facial Cleanser, Korean skincare products, etc.) that will help the user's skin issue (e.g. acne, dryness, redness, hyperpigmentation) in bullet points.
      5. Give specific steps in numbered bullet points using the products and brands you recommended in step 4 to help the user's skin issue. For example:
        - Step 1: Use the CeraVe PM Facial Cleanser to clean your face.
        - Step 2: Use the Anua Heartleaf 77 Soothing Toner to tone your face.
        - Step 3: Use the Skin1004 Snail 96 Mucin Power Essence to hydrate your face.
      Give the steps in the morning and evening.
      6. Recommend diet plans for the user. Provide a list of specific ingredients and how they help the skin condition (e.g. leafy greens, salmon, ginger, lemons, etc.) in bullet points.
      
      When giving your response, make sure to consider the user's current products: #{user.current_products.present? ? user.current_products : "None specified"} and main skin problem concerns: #{user.skin_problem.present? ? user.skin_problem : "General skin health"}.
      Give your response in a concise and to the point manner and at a 5th grade reading level.
    PROMPT
  
    if mobile_request
      base_prompt += <<~MOBILE_PROMPT
        First, analyze whether the image is a selfie, food picture, or skincare product.
        
        If it's a selfie, return response in JSON format with these exact keys:
        {
          "condition": {
            "primary_observations": [
              "Slight shine in the T-zone",
              "Some texture or unevenness on cheeks",
              "Skin may appear mildly dry in some areas"
            ],
            "summary": "Skin shows a mix of oiliness and dryness, which may be common with combination skin types.",
            "possible_factors": [
              "Lifestyle or environmental exposure",
              "Washing the face too frequently",
              "Lack of consistent hydration"
            ]
          },
          "products": [
            "CeraVe Foaming Facial Cleanser – commonly used by individuals with combination or oily skin types",
            "The Ordinary Niacinamide 10% + Zinc 1% – popular for routines focused on visible texture and shine",
            "CeraVe Daily Moisturizing Lotion – lightweight hydration often used for everyday care",
            "EltaMD UV Clear SPF 46 – frequently chosen for its lightweight sun protection"
          ],
          "disclaimer": "Note: These suggestions are for general skincare guidance only and do not constitute medical advice.",
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
          "category": "skin",
          "skin_health": "5/10"
        }

        #{if subscribed && previous_analysis && previous_analysis[:primary_observations] && previous_analysis[:summary]
          <<~PREVIOUS_ANALYSIS

            IMPORTANT: This user is subscribed and has a previous skin analysis. Please compare the current skin selfie to their previous analysis:

            Previous Analysis Summary: #{previous_analysis[:summary]}
            Previous Primary Observations: #{previous_analysis[:primary_observations].join(', ')}

            In your analysis, please:
            - Compare the current skin condition to the previous analysis AND most importantly, use language that indicates comparison to the previous analysis (e.g. "Your skin has improved compared to the last analysis")
            - Note any improvements or changes since the last analysis
            - Mention if the skin condition has gotten better, worse, or stayed the same
            - Adjust your recommendations based on the progression from the previous analysis
          PREVIOUS_ANALYSIS
        end}
    
        If it's a food picture, analyze each item for antioxidants vs oxidants levels. Make sure the percentage of oxidants and antioxidants add up to 100% and round up the the nearest integer and give a descriptive breakdown of the effects on skin, and return in JSON format:
        {
          "ingredients": [
            "Congee with preserved vegetables: 40% oxidants, 60% antioxidants",
            "Scallion pancake: 70% oxidants, 30% antioxidants",
            "Fried dough stick (youtiao): 80% oxidants, 20% antioxidants"
          ],
          "total": ["Total meal average: 63% oxidants, 37% antioxidants"],
          "skin_health": "4/10",
          "total_oxidants": "63%",
          "total_antioxidants": "37%",
          "category": "meal",
          "effects_on_skin": "The meal scores low on skin health, the fried dough stick and scallion pancake are high in oxidants, which can worsen acne or cause a breakout. The congee with preserved vegetables is high in antioxidants, which can help protect skin damage and reduce aging."
        }
        
        If it's a skincare product, analyze for ingredients of the skincare product that affects the user's skin problem (#{user.skin_problem.present? ? user.skin_problem : "general skin health"}). Give a descriptive breakdown and return in JSON format like so:
        {
          "good_ingredients": [
            "Niacinamide - reduces oil production and minimizes pores, excellent for acne-prone skin",
            "Hyaluronic Acid - provides deep hydration without clogging pores",
            "Salicylic Acid - gentle exfoliation helps unclog pores and reduce breakouts",
            "Snail Secretion Filtrate - promotes healing and boosts hydration, great for irritated or damaged skin",
            "Allantoin - soothes and protects skin barrier, helps with inflammation and dryness",
            "Panthenol - improves moisture retention and skin elasticity, calms irritation"
          ],
          "bad_ingredients": [
            "Coconut Oil - highly comedogenic and can clog pores, may worsen acne",
            "Fragrance - can cause irritation and inflammation, especially problematic for sensitive acne-prone skin",
            "Isopropyl Myristate - known pore-clogging ingredient that can trigger breakouts",
            "Phenoxyethanol - can cause irritation for sensitive skin when used in high concentrations"
          ],
          "category": "product"
        }
    
        IMPORTANT INSTRUCTIONS:
        #{user.current_products.present? ? 
          "- The user currently uses: #{user.current_products}. Consider which of these products to keep, modify, or replace in your recommendations." : 
          "- The user hasn't specified current products, so provide a complete routine."
        }
        #{user.skin_problem.present? ? 
          "- Focus recommendations on addressing: #{user.skin_problem}. For product analysis, specifically identify ingredients that help or harm this condition." : 
          "- Provide general skin health recommendations."
        }
        - If current products are good, mention keeping them and suggest complementary products
        - If current products may be causing issues, suggest gentler alternatives
        - Make sure all products recommended are noncomedogenic
        - Tailor the routine complexity based on what they're already doing
        - Make dietary recommendations specific to their skin concerns
        - For product analysis, be specific about how each ingredient affects their particular skin concern
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
    parsed_content = nil
  
    if json_requested && content
      json_string = nil
  
      # Extract from markdown block
      if content.include?('```json')
        json_match = content.match(/```json\s*(\{.*?\})\s*```/m)
        json_string = json_match[1] if json_match
      else
        json_string = content
      end
  
      if json_string
        begin
          parsed_content = JSON.parse(json_string)
        rescue JSON::ParserError => e
          Rails.logger.warn "Initial JSON parse failed: #{e.message}"
          
          # Try sanitizing Ruby hash (e.g. `=>`, nil)
          sanitized = json_string
                        .gsub(/=>/, ':')
                        .gsub(/nil/, 'null')
                        .gsub(/:(\s)?([a-zA-Z_][a-zA-Z0-9_]*)/, ':"\\2"') # unquoted keys
          begin
            parsed_content = JSON.parse(sanitized)
          rescue JSON::ParserError => fallback_error
            Rails.logger.error "Sanitized parse failed: #{fallback_error.message}"
            parsed_content = nil
          end
        end
      end
    end
  
    {
      diagnosis: parsed_content || {},
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