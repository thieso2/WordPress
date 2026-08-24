# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Health do
  describe ".report" do
    it "reports the runtime and the database as passing" do
      report = described_class.report
      labels = report.good.map(&:label)
      expect(labels).to include("Your site is running a supported runtime")
      expect(labels).to include("Your database is reachable")
    end

    # The one legacy check that maps to a real setting here (options-reading blog_public).
    it "flags discouraged search engines as a recommendation when blog_public is off" do
      Configuration::Setting.set("blog_public", "0")
      report = described_class.report
      expect(report.recommended.map(&:label)).to include(
        "Search engines are discouraged from indexing this site."
      )
      expect(report.issue_count).to be >= 1
    end

    it "passes the visibility check when blog_public is on" do
      Configuration::Setting.set("blog_public", "1")
      report = described_class.report
      expect(report.good.map(&:label)).to include("Search engine indexing is enabled.")
    end
  end

  describe ".info" do
    it "returns Server, Database and Content sections" do
      expect(described_class.info.keys).to include("Server", "Database", "Content")
      expect(described_class.info["Server"]["Ruby version"]).to eq(RUBY_VERSION)
    end
  end
end

# BR-MIGRATE-352/355 — the direct/async split and the loopback (job-queue) test, added in
# Wave 5. Labels verified verbatim against the oracle (get_test_loopback_requests(),
# class-wp-site-health.php:2081/2100; badge :2084-2085).
RSpec.describe Platform::Health, "site-health tests (Wave 5)" do
  describe "the direct/async split (BR-MIGRATE-352)" do
    it "runs only the DIRECT battery during .report" do
      expect(described_class.report.results.map(&:mode_name)).to all(eq(:direct))
    end

    it "exposes the ASYNC battery separately, not during .report" do
      labels = described_class.report.results.map(&:label)
      expect(labels).not_to include("Your site can perform loopback requests",
                                    "Your site could not complete a loopback request")
      expect(described_class.async_results.map(&:mode_name)).to all(eq(:async))
    end
  end

  describe "the loopback test (BR-MIGRATE-355) — 'can the job queue run?'" do
    it "passes with the VERBATIM legacy label when the queue is runnable" do
      allow(described_class).to receive(:job_queue_runnable?).and_return(true)
      result = described_class.loopback_check
      expect(result.label).to eq("Your site can perform loopback requests")
      expect(result.status).to eq(:good)
      expect(result).to be_async
    end

    it "fails critical with the VERBATIM legacy label when the queue is unreachable" do
      allow(described_class).to receive(:job_queue_runnable?).and_return(false)
      result = described_class.loopback_check
      expect(result.label).to eq("Your site could not complete a loopback request")
      expect(result.status).to eq(:critical)
    end

    it "treats an unconfigured queue adapter as not runnable" do
      allow(ActiveJob::Base).to receive(:queue_adapter_name).and_return("")
      expect(described_class.job_queue_runnable?).to be(false)
    end

    it "treats an in-process adapter (async/inline/test) as runnable" do
      allow(ActiveJob::Base).to receive(:queue_adapter_name).and_return(:async)
      expect(described_class.job_queue_runnable?).to be(true)
    end
  end

  describe "the REST shape (BR-MIGRATE-356)" do
    it "returns get_test_loopback_requests()'s document, badge verbatim, description in <p>" do
      allow(described_class).to receive(:job_queue_runnable?).and_return(true)
      doc = described_class.loopback_rest_result
      expect(doc[:test]).to eq("loopback_requests")
      expect(doc[:badge]).to eq(label: "Performance", color: "blue")
      expect(doc[:status]).to eq("good")
      expect(doc[:label]).to eq("Your site can perform loopback requests")
      expect(doc[:description]).to start_with("<p>").and end_with("</p>")
      expect(doc[:actions]).to eq("")
    end
  end
end
