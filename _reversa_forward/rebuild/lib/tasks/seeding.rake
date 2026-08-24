# frozen_string_literal: true

namespace :oracle do
  desc "Seed PostgreSQL from the WordPress oracle's MySQL corpus (one-way, idempotent)"
  task seed: :environment do
    require "seeding/pipeline"

    puts "Reversa · oracle corpus seeding pipeline (Wave 0)"
    puts "  source: #{Seeding::Legacy::CONFIG[:database]} @ #{Seeding::Legacy::CONFIG[:host]} (SELECT only)"
    puts "  target: #{ActiveRecord::Base.connection_db_config.database}"
    puts

    pipeline = Seeding::Pipeline.new
    report = pipeline.call
    report.render

    failures = pipeline.verification_failures
    unless failures.empty?
      warn "❌ #{failures.length} quality validation(s) FAILED."
      failures.each { |f| warn "   #{f[:label]}: expected #{f[:expected]}, got #{f[:actual]}" }
    end

    # ⚠️ handoff.md step 9: "The dead-letter queue must fail the run — a pipeline that
    # quietly coerces bad input into defaults would still fill the database and destroy
    # the signal."
    if report.dead_letters.any? || failures.any?
      abort "❌ SEEDING RUN FAILED. Nothing was committed."
    end
    puts "✅ Corpus round-tripped. Dead-letter queue empty; all quality validations passed."
  end

  desc "Inventory the oracle corpus without loading anything"
  task inventory: :environment do
    require "seeding/pipeline"
    Seeding::Pipeline.new.inventory
  end
end
