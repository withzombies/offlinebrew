# Task 2.4: Update URL Shims for Casks

## Objective

Ensure `brew-offline-curl` and `brew-offline-git` properly handle cask-specific download patterns and edge cases.

## Background

Casks download from diverse sources (CDNs, vendor sites) with different URL patterns than formulae. The shims may need adjustments to handle:
- URLs with query parameters
- Redirects
- Content-disposition headers
- Different user-agents

## Prerequisites

- Task 2.1, 2.2, 2.3 completed

## Implementation Steps

### Step 1: Handle URLs with Query Parameters

Cask URLs often have query strings: `https://example.com/download?version=1.0&arch=x64`

Edit `mirror/bin/brew-offline-curl`:

**Find the URL matching section:**

```ruby
urls = ARGV.select { |arg| URI.regexp(%w[http https]) =~ arg }
mirror_urls = urls.map { |url| URI.join(config[:baseurl], urlmap[url]) }
```

**Replace with:**

```ruby
urls = ARGV.select { |arg| URI.regexp(%w[http https]) =~ arg }

mirror_urls = urls.map do |url|
  # Try exact match first
  if urlmap[url]
    URI.join(config[:baseurl], urlmap[url])
  else
    # Try without query parameters (cask URLs often have query strings)
    url_without_query = url.split("?").first
    if urlmap[url_without_query]
      URI.join(config[:baseurl], urlmap[url_without_query])
    else
      # Try without fragment
      url_without_fragment = url.split("#").first
      if urlmap[url_without_fragment]
        URI.join(config[:baseurl], urlmap[url_without_fragment])
      else
        verbose "WARNING: No mirror URL found for #{url}"
        verbose "Allowing original URL (will fail if offline)"
        url  # Return original URL
      end
    end
  end
end
```

### Step 2: Add URL Normalization

Create `mirror/lib/url_helpers.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"

# URLHelpers: Utilities for URL manipulation and matching
module URLHelpers
  # Normalize a URL for matching against urlmap
  # Handles query params, fragments, trailing slashes, etc.
  # Args:
  #   url: String URL
  # Returns: Array of String URLs to try matching
  def self.normalize_for_matching(url)
    variants = []

    # Original URL
    variants << url

    # Without query string
    variants << url.split("?").first if url.include?("?")

    # Without fragment
    variants << url.split("#").first if url.include?("#")

    # Without both
    variants << url.split("?").first.split("#").first if url.include?("?") || url.include?("#")

    # With/without trailing slash
    if url.end_with?("/")
      variants << url.chomp("/")
    else
      variants << "#{url}/"
    end

    # URL decoded version (some URLs have %20 for spaces, etc.)
    require "uri"
    variants << URI.decode_www_form_component(url) rescue nil

    variants.compact.uniq
  end

  # Find a URL in urlmap, trying multiple variants
  # Args:
  #   url: String URL to find
  #   urlmap: Hash of URL mappings
  # Returns: String mapped filename or nil
  def self.find_in_urlmap(url, urlmap)
    normalize_for_matching(url).each do |variant|
      return urlmap[variant] if urlmap[variant]
    end

    nil
  end
end
```

**Update brew-offline-curl to use it:**

```ruby
require_relative "../lib/url_helpers"

# In the URL mapping section:
mirror_urls = urls.map do |url|
  mapped_file = URLHelpers.find_in_urlmap(url, urlmap)

  if mapped_file
    URI.join(config[:baseurl], mapped_file)
  else
    verbose "WARNING: No mirror URL found for #{url}"
    verbose "This download will fail if offline"
    url  # Return original
  end
end
```

### Step 3: Update brew-mirror to Store URLs Consistently

Edit `mirror/bin/brew-mirror`:

**In the urlmap creation section, ensure consistent URL storage:**

```ruby
# Add to urlmap (ensure consistent format)
clean_url = url_str.split("?").first.split("#").first
urlmap[url_str] = new_location.basename.to_s

# Also add the clean URL as an alias for easier matching
urlmap[clean_url] = new_location.basename.to_s unless clean_url == url_str
```

### Step 4: Test URL Shim with Verbose Output

Add better debugging to `brew-offline-curl`:

**At the top, add:**

```ruby
def debug(msg)
  if ENV["HOMEBREW_VERBOSE"] || ENV["BREW_OFFLINE_DEBUG"]
    STDERR.puts "[brew-offline-curl] #{msg}"
  end
end
```

**Use throughout:**

```ruby
debug "Looking up URL: #{url}"
debug "Trying variants: #{URLHelpers.normalize_for_matching(url).join(", ")}"

if mapped_file
  debug "✓ Found mapping: #{url} -> #{mapped_file}"
else
  debug "✗ No mapping found for: #{url}"
end
```

### Step 5: Handle HEAD Requests

Homebrew sometimes makes HEAD requests to check file existence:

**In `brew-offline-curl`, detect HEAD requests:**

```ruby
# Check if this is a HEAD request
is_head_request = ARGV.include?("-I") || ARGV.include?("--head")

if is_head_request
  debug "HEAD request detected"
  # For HEAD requests, just let them through to the mirror
  # The mirror server should handle HEAD requests properly
end
```

## Testing

### Test 1: Test URL Normalization

Create `mirror/test/test_url_helpers.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/url_helpers"

puts "URL Normalization Test"
puts "=" * 50

test_cases = [
  "https://example.com/file.dmg",
  "https://example.com/file.dmg?version=1.0",
  "https://example.com/file.dmg#anchor",
  "https://example.com/file.dmg?v=1&arch=x64",
  "https://example.com/path/",
]

test_cases.each do |url|
  puts "\nURL: #{url}"
  variants = URLHelpers.normalize_for_matching(url)
  variants.each do |variant|
    puts "  - #{variant}"
  end
end
```

Run it:

```bash
ruby mirror/test/test_url_helpers.rb
```

### Test 2: Test Shim with Real Cask

Mirror a cask and test the shim:

```bash
export BREW_OFFLINE_DEBUG=1
ruby mirror/bin/brew-offline-install --cask firefox
```

Look for debug output showing URL lookups.

### Test 3: Test URL Matching

Create a test urlmap and verify matching works:

```bash
cat > /tmp/test_urlmap.json << 'EOF'
{
  "https://example.com/file.dmg": "abc123.dmg",
  "https://example.com/other.zip": "def456.zip"
}
EOF
```

```ruby
# Test script
require "json"
require_relative "mirror/lib/url_helpers"

urlmap = JSON.parse(File.read("/tmp/test_urlmap.json"))

test_urls = [
  "https://example.com/file.dmg",           # Exact match
  "https://example.com/file.dmg?ver=1.0",   # With query
  "https://example.com/file.dmg#download",  # With fragment
]

test_urls.each do |url|
  result = URLHelpers.find_in_urlmap(url, urlmap)
  puts "#{url} -> #{result || 'NOT FOUND'}"
end
```

**Expected:**
```
https://example.com/file.dmg -> abc123.dmg
https://example.com/file.dmg?ver=1.0 -> abc123.dmg
https://example.com/file.dmg#download -> abc123.dmg
```

## Acceptance Criteria

✅ You're done when:

1. Shims handle URLs with query parameters
2. Shims handle URLs with fragments
3. URL normalization module works correctly
4. Debug output available with BREW_OFFLINE_DEBUG
5. HEAD requests work properly
6. No URL matching failures for common cask URLs
7. Tests pass

## Troubleshooting

### Issue: "No mirror URL found" for valid cask

**Solution:**
Check the urlmap.json:

```bash
cat /tmp/test-mirror/urlmap.json | jq 'keys[]' | grep -i firefox
```

Enable debug mode to see what URLs are being looked up:

```bash
export BREW_OFFLINE_DEBUG=1
```

### Issue: Downloads still go to internet

**Solution:**
Verify shims are being called:

```bash
which brew-offline-curl
echo $HOMEBREW_CURL_PATH
```

Should show the shim script path.

### Issue: URL variants not matching

**Solution:**
Add more variants to URLHelpers.normalize_for_matching based on the specific URL patterns you're seeing.

## Commit Message

When done:

```bash
git add mirror/bin/brew-offline-curl mirror/lib/url_helpers.rb mirror/test/test_url_helpers.rb
git commit -m "Task 2.4: Improve URL shims for cask support

- Add URL normalization for query parameters and fragments
- Create URLHelpers module for consistent URL matching
- Add debug output for troubleshooting
- Handle HEAD requests properly
- Support URL variants in urlmap lookups
- Store multiple URL variants in brew-mirror
- Add tests for URL matching"
```

## Next Steps

Phase 2 complete! Proceed to **Task 3.1: Multi-Tap Configuration Support** (Phase 3)
