module Api
  module V1
    class CodeMappingsController < ApplicationController
      before_action :authenticate_user!

      def create
        description = params[:description]
        codes = CodeMappingService.new(description).call
        CodeMapping.create!(user: current_user, description: description, codes: codes)
        render json: codes, status: :created
      end
    end
  end
end