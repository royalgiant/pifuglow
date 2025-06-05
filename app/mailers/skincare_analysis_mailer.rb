class SkincareAnalysisMailer < ApplicationMailer
  def analysis_result
    @email = params[:email]
    @diagnosis = params[:diagnosis]

    mail(
      to: @email,
      subject: "Your Skincare Analysis Results Are Ready! 🧴"
    )
  end
end