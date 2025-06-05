class SkincareAnalysisMailer < ApplicationMailer
  def analysis_result
    @email = params[:email]
    @diagnosis = params[:diagnosis]
    @image_url = params[:image_url]

    mail(
      to: @email,
      subject: "Your Skincare Analysis Results Are Ready! 🧴"
    )
  end
end