# frozen_string_literal: true

require 'json'
require 'base64'
require 'open3'

module Sanitizing
  # Drives the PHP oracle for the differential harness.
  #
  # One PHP process for the whole batch: WordPress boots once and answers N
  # cases. Spawning `php -r` per input is orders of magnitude too slow to fuzz.
  module Oracle
    RUNNER = File.expand_path('php/oracle.php', __dir__)
    BOOTSTRAP = File.expand_path(
      '../../../../../oracle/wordpress/tools/_bootstrap.php', __dir__
    )

    module_function

    def available?
      File.exist?(BOOTSTRAP) && !which_php.nil?
    end

    def which_php
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).map { |d| File.join(d, 'php') }.find do |p|
        File.executable?(p) && !File.directory?(p)
      end
    end

    # cases: [[fn, arg_string], ...] -> [result_string_or_nil, ...]
    def run(cases)
      payload = JSON.generate(
        cases: cases.map { |fn, arg| { fn: fn, args: [Base64.strict_encode64(arg.dup.force_encoding(Encoding::BINARY))] } }
      )

      out, err, status = Open3.capture3('php', RUNNER, stdin_data: payload)
      raise "PHP oracle failed (#{status.exitstatus}): #{err}" unless status.success?

      # An exit-0 process that wrote nothing means the oracle died before it
      # could answer (it echoes its JSON as the very last statement). Fail with
      # that fact rather than with a confusing JSON::ParserError.
      raise "PHP oracle produced no output (status #{status.inspect}, stderr: #{err.inspect})" if out.empty?

      JSON.parse(out).fetch('results').map { |r| r.nil? ? nil : Base64.decode64(r).force_encoding(Encoding::BINARY) }
    end
  end
end
