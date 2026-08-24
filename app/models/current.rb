# What the request being served knows about itself. Reset between requests by
# Rails, and never set outside one — a job has no request to be a demo of, so
# DemoMode is off everywhere the real figures are written down.
class Current < ActiveSupport::CurrentAttributes
  attribute :demo
end
