# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-351/349/350. The legacy schema MECHANISM is absorbed by Rails migrations;
# what survives as observable is the version marker and the "current vs target" gate. The
# test database is loaded from db/structure.sql with every migration recorded, so it is by
# construction "up to date" — which is exactly the state the gate must report.
RSpec.describe Platform::SchemaVersion do
  it "keeps the legacy $wp_db_version as provenance (version.php:26)" do
    expect(described_class::LEGACY_DB_VERSION).to eq(61_833)
  end

  describe "the single schema marker (BR-MIGRATE-351)" do
    it "reads current as the highest recorded migration and target as the newest on disk" do
      expect(described_class.current).to eq(described_class.target)
    end
  end

  describe "the surviving 'current vs target' gate (BR-MIGRATE-349/350)" do
    it "reports the loaded schema as up to date with nothing pending" do
      expect(described_class.up_to_date?).to be(true)
      expect(described_class.pending).to eq([])
    end

    it "reports the three facts a diagnostics surface reads" do
      report = described_class.report
      expect(report).to include(:current, :target, :up_to_date, :pending, :legacy_db_version)
      expect(report[:up_to_date]).to be(true)
      expect(report[:legacy_db_version]).to eq(61_833)
    end
  end
end
