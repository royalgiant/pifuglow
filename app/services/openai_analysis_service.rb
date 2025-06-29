class OpenaiAnalysisService
  MAX_RETRIES = 10
  INITIAL_DELAY = 1

  def analyze_image(image_url, mobile_request = false)
    prompt = generate_analysis_prompt(mobile_request)
    response = call_openai_api(prompt, image_url)
    parse_openai_response(response)
  end

  private

  def generate_analysis_prompt(mobile_request)
    base_prompt = <<~PROMPT
      Please analyze this selfie image for skin conditions and provide a diagnosis:
      1. Identify any visible skin conditions (e.g., acne, dryness, redness, hyperpigmentation).
      2. Describe the severity of each condition (mild, moderate, severe).
      3. Suggest potential causes (e.g., environmental factors, diet, skincare routine).
      4. Provide specific products & brands (e.g CeraVe Moisturizing Cream, CeraVe PM Facial Cleanser, Korean skincare products, etc.)that will help the user's skin issue (e.g. acne, dryness, redness, hyperpigmentation) in bullet points.
      5. Give specific steps in numbered bullet points using the products and brands you recommended in step 4 to help the user's skin issue. For example:
        - Step 1: Use the CeraVe PM Facial Cleanser to clean your face.
        - Step 2: Use the Anua Heartleaf 77 Soothing Toner to tone your face.
        - Step 3: Use the Skin1004 Snail 96 Mucin Power Essence to hydrate your face.
      Give the steps in the morning and evening.
      6. Recommend diet plans for the user. Provide a list of specific ingredients and how they help the skin condition (e.g. leafy greens, salmon, ginger, lemons, etc.) in bullet points.
      Make your response concise and to the point and at a 5th grade reading level.
    PROMPT

    if mobile_request
      base_prompt += "\n\nReturn the response in JSON format with the following structure: steps 1, 2, and 3 should be returned with key 'condition', step 4 returned with key 'products', step 5 with key 'routine', and step 6 with key 'diet'."
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

  def parse_openai_response(response)
    {
      diagnosis: response.dig("choices", 0, "message", "content"),
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