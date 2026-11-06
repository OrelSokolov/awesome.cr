# LongParameterList — a method that takes a crowd.
# The bad snippet for `awesome doc` and examples/awful; two issues:
# 8 and 9 parameters — concepts (Message, Page setup) want to exist.

class Mailer
  def send(to, from, subject, body, cc, bcc, reply_to, attachments)
  end
end

class Report
  def initialize(title, subtitle, author, from, to, width, height, margin, footer)
  end
end
