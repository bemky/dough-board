require "test_helper"

# Which queue each job lands on is a deployment concern that only shows up in
# production, so pin it here: config/sidekiq.yml has to name every queue a job
# uses, or that job is enqueued and never run.
class QueuesTest < ActiveSupport::TestCase

  CONFIGURED = YAML.load_file(Rails.root.join("config/sidekiq.yml")).fetch(:queues).freeze

  def configured_names
    CONFIGURED.map { |queue| queue.is_a?(Array) ? queue.first : queue }
  end

  test "the slow scrapes are not on the same queue as everything else" do
    assert_equal "scrapes", LoadSplitsJob.new.queue_name
    assert_equal "default", DerivePositionsJob.new.queue_name
    assert_equal "default", AmortizeLoanJob.new.queue_name
    assert_equal "default", ConnectionJob.new.queue_name
  end

  test "every queue a job uses is one the workers are told to watch" do
    used = [LoadSplitsJob, DerivePositionsJob, AmortizeLoanJob, ConnectionJob].map { |job| job.new.queue_name }
    assert_empty used.uniq - configured_names
  end

  # Strict ordering would let a few thousand scrapes starve everything behind
  # them, which is the whole reason they were moved off `default`.
  test "the queues are weighted rather than strictly ordered" do
    assert CONFIGURED.all? { |queue| queue.is_a?(Array) && queue.length == 2 },
      "expected [name, weight] pairs, got #{CONFIGURED.inspect}"
    assert_operator weight_for("default"), :>, weight_for("scrapes")
  end

  def weight_for(name)
    CONFIGURED.find { |queue| queue.first == name }.last
  end

end
