class ClaudeAnalysisService
  MAX_RETRIES = 10
  INITIAL_DELAY = 1

  def analyze_transcription(transcription)
    prompt = generate_analysis_prompt(transcription)
    response = call_claude_api(prompt)
    parse_claude_response(response)
  end

  private

  def generate_analysis_prompt(transcription)
    <<~PROMPT
      Please analyze this YouTube video transcription and identify:
      1. The primary storytelling framework being used (if any)
      2. Key story elements and how they align with common frameworks
      3. Strengths in the storytelling structure
      4. Areas that could be improved
      5. Emotional hooks and engagement techniques used
      
      Transcription:
      #{transcription}
    PROMPT
  end

  def system_prompt
    "You are an expert in storytelling and video script analysis. Analyze this video transcription for its storytelling structure, emotional engagement, and areas for improvement."
  end

  def call_claude_api(prompt)
    client = Anthropic::Client.new
    retries = 0

    begin
      client.messages(
        parameters: {
          model: "claude-3-haiku-20240307",
          system: system_prompt,
          messages: [
            { role: "user", content: prompt }
          ],
          max_tokens: 4096
        }
      )
    rescue Faraday::TooManyRequestsError => e
      retries += 1
      if retries <= MAX_RETRIES
        delay = INITIAL_DELAY * (2 ** (retries - 1)) # Exponential backoff: 1s, 2s, 4s, 8s, 16s, etc.
        Rails.logger.info "Claude API rate limit hit, retrying in #{delay}s (attempt #{retries}/#{MAX_RETRIES})"
        sleep(delay)
        retry
      else
        Rails.logger.error "Claude API max retries (#{MAX_RETRIES}) reached: #{e.message}"
        raise e
      end
    end
  end

  def parse_claude_response(response)
    {
      analysis: response["content"][0]["text"],
      timestamp: Time.current,
      model_info: {
        name: response["model"],
        usage: {
          input_tokens: response["usage"]["input_tokens"],
          output_tokens: response["usage"]["output_tokens"],
          total_tokens: response["usage"]["input_tokens"] + response["usage"]["output_tokens"]
        }
      }
    }
  end
end