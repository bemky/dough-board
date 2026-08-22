class ApplicationJob < ActiveJob::Base
  # Most jobs are safe to ignore deserialization errors for:
  # discard_on ActiveJob::DeserializationError

  # Most jobs are safe to retry if the underlying infrastructure is transient:
  # retry_on ActiveRecord::Deadlocked
end
