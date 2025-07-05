class ContactMailer < ApplicationMailer
  default from: 'noreply@pifuglow.com'

  def contact_email(email, message)
    @email = email
    @message = message
    
    mail(
      to: 'donald@pifuglow.com',
      subject: 'Contact Form Submission'
    )
  end
end