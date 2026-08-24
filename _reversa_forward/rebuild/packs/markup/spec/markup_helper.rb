# frozen_string_literal: true

# Loads the `markup` pack for RSpec.
#
# topology_decision.md option 3: this pack is pure Ruby with zero dependencies. It does
# not require Rails, ActiveSupport, ActiveRecord, or any other pack, so the specs load
# the source files directly instead of relying on Zeitwerk. Files under `app/` never
# `require` one another, which is what lets both this loader and the Rails autoloader
# work without conflict.
# `processor.rb` names its superclass at load time, so it must come last; everything
# else is order-independent.
files = Dir[File.expand_path("../app/markup/*.rb", __dir__)].sort
files.partition { |file| File.basename(file) != "processor.rb" }.flatten.each { |file| require file }

# Runs a snippet against the seeded WordPress 7.2-alpha-63330 PHP oracle and returns its
# stdout. Used by the differential specs; skipped automatically when PHP is unavailable.
module MarkupOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  def self.available?
    return @available if defined?(@available)

    @available = File.exist?(BOOTSTRAP) && system("which php > /dev/null 2>&1")
  end

  def self.run(php_source)
    raise "PHP oracle unavailable" unless available?

    require "open3"
    script = "require #{BOOTSTRAP.inspect}; #{php_source}"
    out, err, status = Open3.capture3("php", "-r", script)
    raise "oracle failed: #{err}" unless status.success?

    out
  end
end
