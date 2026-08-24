# frozen_string_literal: true

require_relative '../pack_helper'

# parity_tests/05-kses-sanitization.feature, @invariant:
#   "Sanitized markup is a distinct type"
#   Given a value that has not passed through the sanitizing pack
#   When code attempts to render it as trusted markup
#   Then the type system rejects the value
#
# This is the one guarantee the target ADDS. architecture.md §4 records the
# legacy's escaping discipline as "convention only, no type system" (F-FMT-02).
RSpec.describe Sanitizing::SafeHtml do
  it 'wraps content that has been through the post allowlist' do
    safe = described_class.from_post_content('<b>ok</b><script>bad()</script>')
    expect(safe).to be_a(described_class)
    expect(safe.to_s).to eq('<b>ok</b>bad()')
  end

  it 'wraps content filtered for any named context' do
    expect(described_class.from('<div>x</div>', 'data').to_s).to eq('x')
  end

  it 'rejects a bare String where trusted markup is required' do
    expect { described_class.assert!('<script>alert(1)</script>') }
      .to raise_error(TypeError, /expected Sanitizing::SafeHtml, got String/)
  end

  it 'accepts a SafeHtml where trusted markup is required' do
    safe = described_class.from_post_content('<b>ok</b>')
    expect(described_class.assert!(safe)).to equal(safe)
  end

  it 'cannot be constructed around unfiltered markup' do
    expect { described_class.new('<script>alert(1)</script>') }
      .to raise_error(ArgumentError, /use SafeHtml.from_post_content or SafeHtml.from/)
  end

  it 'is immutable once constructed' do
    safe = described_class.from_post_content('<b>ok</b>')
    expect(safe).to be_frozen
    expect { safe.to_s << 'x' }.to raise_error(FrozenError)
  end

  it 'compares by content and only ever to another SafeHtml' do
    a = described_class.from_post_content('<b>ok</b>')
    b = described_class.from_post_content('<b>ok</b>')
    expect(a).to eq(b)
    expect(a).not_to eq('<b>ok</b>')
  end
end
