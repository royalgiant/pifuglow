class CodeMappingsController < ApplicationController
  before_action :authenticate_user!

  def new
    @code_mapping = CodeMapping.new
  end

  def create
    @code_mapping = CodeMapping.new(user: current_user, description: params[:code_mapping][:description].gsub("\n", " "))
    if @code_mapping.save
      @codes = CodeMappingService.new(@code_mapping.description).call
      @code_mapping.update(codes: @codes)
      render :show
    else
      render :new
    end
  end

  def export
    @code_mapping = current_user.code_mappings.find(params[:id])
    send_data generate_csv(@code_mapping.codes), filename: "codes-#{Date.today}.csv"
  end

  private

  def generate_csv(codes)
    CSV.generate do |csv|
      csv << ["Code", "Description", "Cost"]
      codes[:icd10].each { |c| csv << [c[:code], c[:description], "N/A"] }
      codes[:cpt].each { |c| csv << [c[:code], c[:description], c[:cost]] }
      codes[:hcpcs].each { |c| csv << [c[:code], c[:description], "N/A"] }
    end
  end
end