# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-343..351. The most-absorbed group: the update CHECK (343/344/345) is VOID
# (no wordpress.org to poll); the schema rules (349/350/351) defer to SchemaVersion; the
# reproduced observables are maintenance mode (347) and verify-before-extract (346).
RSpec.describe Platform::Updates do
  it "records the update-check rules as void (no external update server, BR-MIGRATE-343/344/345)" do
    expect(described_class::VOID_UPDATE_CHECK).to eq(%w[BR-MIGRATE-343 BR-MIGRATE-344 BR-MIGRATE-345])
  end

  it "defers 'is the schema current?' to Platform::SchemaVersion (BR-MIGRATE-349/350/351)" do
    expect(described_class.schema_current?).to eq(Platform::SchemaVersion.up_to_date?)
  end

  describe Platform::Updates::Maintenance do
    before { described_class.disable }
    after  { described_class.disable }

    it "keeps the legacy 10-minute window (load.php:447)" do
      expect(described_class::WINDOW).to eq(10 * 60)
    end

    it "is inactive when no install is in flight" do
      expect(described_class.active?).to be(false)
    end

    it "reports maintenance while the flag is fresh (BR-MIGRATE-347)" do
      described_class.enable
      expect(described_class.active?).to be(true)
    end

    it "treats a timestamp older than the window as NOT maintenance (:447 staleness)" do
      Rails.cache.write(described_class::CACHE_KEY, (Time.current - (described_class::WINDOW + 5)).to_i)
      expect(described_class.active?).to be(false)
    end

    it "lifts maintenance on disable" do
      described_class.enable
      described_class.disable
      expect(described_class.active?).to be(false)
    end

    it "guarantees maintenance is lifted after #during even when the block raises" do
      expect { described_class.during { raise "boom" } }.to raise_error("boom")
      expect(described_class.active?).to be(false)
    end
  end

  describe ".install_package" do
    it "wraps the package install in maintenance and defers verify/extract to the package" do
      package = instance_double("Egress::Package")
      seen = nil
      allow(package).to receive(:install!) { |_| seen = Platform::Updates::Maintenance.active? }
      Platform::Updates.install_package(package, into: :dest)
      # 347: maintenance is active FOR THE DURATION of the install...
      expect(seen).to be(true)
      # ...and lifted once it returns.
      expect(Platform::Updates::Maintenance.active?).to be(false)
      expect(package).to have_received(:install!).with(into: :dest)
    end
  end
end
