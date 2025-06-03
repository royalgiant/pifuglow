class CodeMappingService
  def initialize(description)
    @description = description
    @missing_codes = { icd10: [], cpt: [], hcpcs: [] } # Track missing codes
  end

  def call
    Rails.cache.fetch("mapping:#{@description.hash}", expires_in: 1.day) do
      client ||= OpenAI::Client.new(
        access_token: Rails.application.credentials.dig(Rails.env.to_sym, :openai, :access_token),
        log_errors: Rails.env.production? ? false : true 
      )

      # Make the API call using ruby-openai
      response = client.chat(
        parameters: {
          model: "gpt-4",
          messages: [
            { role: "system", content: "Map clinical descriptions to ICD-10, CPT, HCPCS codes in JSON: { icd10: [], cpt: [], hcpcs: [] }. Focus on codes relevant to outpatient family practice billing, such as ICD-10 codes for diagnoses, CPT codes for procedures like therapy or radiology, and HCPCS codes for screenings like PSA tests (e.g., G0103)." },
            { role: "user", content: @description }
          ],
          temperature: 0.7
        }
      )

      raw_codes = response.dig("choices", 0, "message", "content")
      Rails.logger.debug("Raw GPT-4 response: #{raw_codes}")
      puts "Raw GPT-4 response: #{raw_codes}"

      codes = JSON.parse(raw_codes)
      result = validate_and_enrich(codes)

      if @missing_codes.values.any?(&:present?)
        missing_message = "Missing codes for description '#{@description}': #{@missing_codes}"
        Rails.logger.info(missing_message)
        puts missing_message
      end

      result
    end
  end

  private

  def validate_and_enrich(codes)
    {
      icd10: codes["icd10"].map do |code|
        icd = Icd10Code.find_by(code: code)
        if icd
          { code: code, description: icd.description }
        else
          @missing_codes[:icd10] << code
          nil
        end
      end.compact,
      cpt: codes["cpt"].map do |code|
        cpt = CptCode.find_by(code: code)
        if cpt
          cost = cpt.cost_estimates&.find_by(region: "default")&.amount
          { code: code, description: cpt.description, cost: cost || "N/A" }
        else
          @missing_codes[:cpt] << code
          nil
        end
      end.compact,
      hcpcs: codes["hcpcs"].map do |code|
        hcpcs = HcpcsCode.find_by("LOWER(code) = ?", code.downcase)
        if hcpcs
          { code: hcpcs.code, description: hcpcs.description }
        else
          @missing_codes[:hcpcs] << code
          nil
        end
      end.compact
    }
  end
end