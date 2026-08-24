# frozen_string_literal: true

require_relative '../pack_helper'

# BR-MIGRATE-297 / BR-FMT-07 — sanitize_option() dispatches per option name.
RSpec.describe Sanitizing::Options do
  it 'dispatches per option name' do
    expect(described_class.sanitize_option('comments_per_page', '-12abc')).to eq(12)
    expect(described_class.sanitize_option('blog_charset', 'UTF-8; drop')).to eq('UTF-8drop')
    expect(described_class.sanitize_option('unknown_option', ' as-is ')).to eq(' as-is ')
  end

  it 'coerces the absint options to a non-negative integer' do
    described_class::ABSINT_OPTIONS.each do |option|
      expect(described_class.sanitize_option(option, '-7')).to eq(7)
    end
  end

  it 'forces posts_per_page to at least 1, and -1 through unchanged' do
    expect(described_class.sanitize_option('posts_per_page', '0')).to eq(1)
    expect(described_class.sanitize_option('posts_per_page', '')).to eq(1)
    expect(described_class.sanitize_option('posts_per_page', '-1')).to eq(-1)
    expect(described_class.sanitize_option('posts_per_page', '-5')).to eq(5)
  end

  it "turns a falsy comment status into 'closed'" do
    expect(described_class.sanitize_option('default_comment_status', '0')).to eq('closed')
    expect(described_class.sanitize_option('default_ping_status', '')).to eq('closed')
    expect(described_class.sanitize_option('default_comment_status', 'open')).to eq('open')
  end

  it 'escapes the site title and tagline' do
    expect(described_class.sanitize_option('blogname', '<b>Site</b>'))
      .to eq('&lt;b&gt;Site&lt;/b&gt;')
  end

  it 'runs the kses data allowlist over the free-text options' do
    expect(described_class.sanitize_option('date_format', '<script>x</script>F j, Y'))
      .to eq('xF j, Y')
  end

  it 'sanitizes each ping site as a URL and drops the empties' do
    expect(described_class.sanitize_option('ping_sites', "http://a.example\n\n  javascript:alert(1)\n"))
      .to eq('http://a.example')
  end

  it 'deduplicates moderation keys' do
    expect(described_class.sanitize_option('disallowed_keys', " a \nb\na\n\n")).to eq("a\nb")
  end

  it 'rejects domains with a double dot or double dash' do
    expect(described_class.sanitize_option('limited_email_domains', "ok.example\nbad--x.example\na..b"))
      .to eq(['ok.example'])
  end

  it 'requires a structure tag in a custom permalink structure' do
    good = described_class.sanitize_option('permalink_structure', '/%postname%/')
    expect(good).to eq('/%postname%/')

    bad = described_class.sanitize_option('permalink_structure', '/blog/')
    expect(bad).to be_a(described_class::Deferred)
    expect(bad.error).to eq(described_class::PERMALINK_ERROR)
  end

  it 'reports the legacy error string verbatim for an invalid site address' do
    result = described_class.sanitize_option('siteurl', 'not a url')
    expect(result).to be_a(described_class::Deferred)
    expect(result.error).to eq(
      'The WordPress address you entered did not appear to be a valid URL. Please enter a valid URL.'
    )
  end

  it 'defers the branches that need site state instead of guessing' do
    # topology_decision.md option 3: this pack has no database, no role registry,
    # no option store and no language list. See README, "sanitize_option".
    described_class::NEEDS_SITE_STATE.each do |option|
      result = described_class.sanitize_option(option, 'anything')
      expect(result).to be_a(described_class::Deferred)
      expect(result.reason).to eq(:needs_site_state)
    end
  end
end
