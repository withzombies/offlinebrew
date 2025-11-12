# Task 2.2: Implement Cask Download Logic (Refinements)

## Objective

Handle edge cases and special download scenarios for casks, including multiple artifacts, appcast updates, and various container formats.

## Background

Task 2.1 implemented basic cask mirroring, but casks have additional complexities:
- Some casks have multiple artifacts (apps, fonts, pkg installers)
- Container formats vary (DMG, PKG, ZIP, 7Z, etc.)
- Some casks use appcast for version checking
- Some casks have language-specific downloads

## Prerequisites

- Task 2.1 completed (Basic cask tap mirroring)

## Implementation Steps

### Step 1: Handle Multiple Download URLs

Some casks may download from multiple URLs. Update the cask mirroring logic in `mirror/bin/brew-mirror`:

**Find the cask iteration section and enhance it:**

```ruby
cask_iterator.each do |cask|
  ohai "Collecting resources for cask: #{cask.token}..."

  begin
    # Collect all URLs from the cask
    urls_to_mirror = []

    # Main cask URL
    if cask.url
      urls_to_mirror << {
        url: cask.url,
        checksum: cask.sha256,
      }
    end

    # Some casks have additional downloads (rare but exists)
    # Check for additional resources if they exist
    if cask.respond_to?(:downloads) && cask.downloads
      cask.downloads.each do |download|
        urls_to_mirror << {
          url: download.url,
          checksum: download.sha256,
        }
      end
    end

    # Skip if no URLs found
    if urls_to_mirror.empty?
      opoo "#{cask.token} has no downloadable URLs, skipping"
      next
    end

    # Download each URL
    urls_to_mirror.each do |item|
      url_obj = item[:url]
      url_str = url_obj.to_s
      checksum = item[:checksum]

      ohai "\tCask URL: #{url_str}"

      # Get downloader
      downloader = url_obj.downloader

      unless BREW_OFFLINE_DOWNLOAD_STRATEGIES.include?(downloader.class)
        opoo "#{cask.token} uses unsupported download strategy: #{downloader.class}"
        next
      end

      # Create identifier
      identifier = if checksum && checksum != :no_check
                     checksum.to_s
                   else
                     # No checksum - use URL hash
                     require "digest"
                     Digest::SHA256.hexdigest(url_str)
                   end

      # Determine file extension
      # Casks can be .dmg, .pkg, .zip, .7z, .tar.gz, etc.
      old_location = downloader.cached_location
      extension = old_location.extname
      extension = ".dmg" if extension.empty?  # Default to .dmg

      new_location = Pathname.new(File.join(options[:directory],
                                            "#{identifier}#{extension}"))

      # Download
      downloader.shutup!
      begin
        downloader.fetch unless new_location.exist?
      rescue StandardError => e
        opoo "Download failed for #{url_str}: #{e.message}"
        next
      end

      # Move to mirror
      if new_location.exist?
        ohai "\tAlready mirrored!"
      else
        FileUtils.mv old_location.to_s, new_location.to_s, force: true
        ohai "\t#{old_location.basename} -> #{new_location.basename}"
      end

      # Add to urlmap
      urlmap[url_str] = new_location.basename.to_s
    end

  rescue StandardError => e
    opoo "Failed to process cask #{cask.token}: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}" if ENV["HOMEBREW_VERBOSE"]
    next
  end

  sleep options[:sleep]
end
```

### Step 2: Handle Container Format Variations

Create `mirror/lib/container_helpers.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# ContainerHelpers: Utilities for handling various cask container formats
module ContainerHelpers
  # Known cask container extensions
  CONTAINER_EXTENSIONS = %w[
    .dmg
    .pkg
    .mpkg
    .zip
    .tar.gz
    .tgz
    .tar.bz2
    .tbz
    .tar.xz
    .txz
    .7z
    .rar
    .app
    .jar
  ].freeze

  # Detect container extension from URL or filename
  # Args:
  #   url: String or URI
  # Returns: String extension (e.g., ".dmg")
  def self.detect_extension(url)
    url_str = url.to_s

    # Try to detect from URL
    CONTAINER_EXTENSIONS.each do |ext|
      return ext if url_str.include?(ext)
    end

    # Check for common patterns
    return ".dmg" if url_str.match?(/\.dmg($|\?|#)/)
    return ".pkg" if url_str.match?(/\.pkg($|\?|#)/)
    return ".zip" if url_str.match?(/\.zip($|\?|#)/)

    # Default to .dmg (most common for macOS apps)
    ".dmg"
  end

  # Verify a downloaded container file
  # Args:
  #   path: Pathname to container file
  # Returns: Boolean
  def self.verify_container(path)
    return false unless path.exist?
    return false if path.size.zero?

    # Basic file type checks
    case path.extname
    when ".dmg"
      # Check DMG magic number
      File.open(path, "rb") do |f|
        magic = f.read(4)
        # DMG files can start with various magic numbers
        return true if ["x\x01\x73\x0D", "mish", "koly"].any? { |m| magic&.include?(m) }
      end
    when ".pkg", ".mpkg"
      # PKG files are xar archives
      File.open(path, "rb") do |f|
        magic = f.read(4)
        return true if magic == "xar!"
      end
    when ".zip"
      # ZIP magic number
      File.open(path, "rb") do |f|
        magic = f.read(4)
        return true if magic == "PK\x03\x04"
      end
    end

    # If we can't verify, assume it's okay
    true
  end

  # Get human-readable size
  # Args:
  #   path: Pathname
  # Returns: String (e.g., "150 MB")
  def self.human_size(path)
    return "0 B" unless path.exist?

    size = path.size
    units = %w[B KB MB GB TB]
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end

    format("%.1f %s", size, units[unit_index])
  end
end
```

**Update brew-mirror to use it:**

```ruby
require_relative "../lib/container_helpers"

# In the download section:
extension = ContainerHelpers.detect_extension(url_str)
new_location = Pathname.new(File.join(options[:directory],
                                      "#{identifier}#{extension}"))

# After download:
if new_location.exist?
  if ContainerHelpers.verify_container(new_location)
    ohai "\t✓ Downloaded: #{ContainerHelpers.human_size(new_location)}"
  else
    opoo "\t⚠ File may be corrupted: #{new_location.basename}"
  end
end
```

### Step 3: Add Progress Tracking for Large Downloads

Cask files can be hundreds of MB. Add progress indication:

**In `mirror/bin/brew-mirror`, before downloading:**

```ruby
# Show expected download size if available
if url_obj.respond_to?(:specs) && url_obj.specs[:size]
  expected_size = url_obj.specs[:size]
  ohai "\tExpected size: #{expected_size / 1024 / 1024} MB"
end

# Check if already cached by Homebrew
if downloader.cached_location.exist?
  cached_size = ContainerHelpers.human_size(downloader.cached_location)
  ohai "\tFound in Homebrew cache: #{cached_size}"
end
```

### Step 4: Handle Download Failures Gracefully

Add retry logic for failed downloads:

**Create `mirror/lib/download_helpers.rb`:**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# DownloadHelpers: Utilities for reliable downloading
module DownloadHelpers
  # Download with retries
  # Args:
  #   downloader: Homebrew download strategy instance
  #   max_retries: Integer (default 3)
  # Returns: Boolean (success)
  def self.fetch_with_retry(downloader, max_retries: 3)
    attempts = 0

    loop do
      attempts += 1

      begin
        downloader.fetch
        return true
      rescue StandardError => e
        if attempts >= max_retries
          warn "Download failed after #{attempts} attempts: #{e.message}"
          return false
        end

        warn "Download attempt #{attempts} failed: #{e.message}"
        warn "Retrying in #{attempts * 2} seconds..."
        sleep attempts * 2
      end
    end
  end

  # Clean up partial downloads
  # Args:
  #   path: Pathname to check and clean
  def self.cleanup_partial(path)
    if path.exist? && path.size.zero?
      warn "Removing zero-byte file: #{path}"
      path.delete
    end
  end
end
```

**Update brew-mirror to use it:**

```ruby
require_relative "../lib/download_helpers"

# Replace the download section:
downloader.shutup!

unless new_location.exist?
  ohai "\tDownloading..."
  success = DownloadHelpers.fetch_with_retry(downloader, max_retries: 2)

  unless success
    opoo "Failed to download #{url_str}"
    next
  end
end
```

### Step 5: Add Cask-Specific Statistics

Track cask mirror statistics:

**In `mirror/bin/brew-mirror`, add after the cask loop:**

```ruby
# After the cask iteration loop ends
if HomebrewPaths.tap_exists?(HomebrewPaths.cask_tap_path)
  cask_count = cask_iterator.count
  cask_files = Dir.glob("#{options[:directory]}/*.{dmg,pkg,zip}").count
  total_size = `du -sh #{options[:directory]}`.split.first

  ohai "Cask mirror statistics:"
  puts "  Casks processed: #{cask_count}"
  puts "  Files downloaded: #{cask_files}"
  puts "  Total mirror size: #{total_size}"
end
```

## Testing

### Test 1: Mirror Multiple Casks

Test with casks that have different container formats:

```bash
rm -rf /tmp/test-cask-mirror
mkdir /tmp/test-cask-mirror

brew ruby mirror/bin/brew-mirror \
  -d /tmp/test-cask-mirror \
  --casks firefox,google-chrome,visual-studio-code \
  -s 2
```

**Expected:**
- Multiple DMG files downloaded
- Different file sizes
- All entries in urlmap.json
- Statistics at the end

### Test 2: Verify Container Files

```bash
ls -lh /tmp/test-cask-mirror/*.dmg
file /tmp/test-cask-mirror/*.dmg
```

**Expected:**
```
-rw-r--r--  1 user  staff   150M Nov 11 10:00 abc123.dmg
-rw-r--r--  1 user  staff   200M Nov 11 10:02 def456.dmg

/tmp/test-cask-mirror/abc123.dmg: zlib compressed data
/tmp/test-cask-mirror/def456.dmg: zlib compressed data
```

### Test 3: Test Download Retry

Simulate a network issue by using a cask with a flaky download:

```bash
# This should retry and eventually succeed or fail gracefully
brew ruby mirror/bin/brew-mirror -d /tmp/test --casks some-cask -s 1
```

### Test 4: Verify Statistics

After mirroring, check that statistics are printed:

**Expected output:**
```
Cask mirror statistics:
  Casks processed: 3
  Files downloaded: 3
  Total mirror size: 500M
```

## Acceptance Criteria

✅ You're done when:

1. Can mirror casks with various container formats (DMG, PKG, ZIP)
2. Large downloads show progress/size information
3. Download failures trigger retry logic
4. Container files are verified after download
5. Statistics are printed after mirroring
6. Partial/corrupted downloads are detected
7. Multiple URLs per cask are handled (if applicable)

## Troubleshooting

### Issue: "File may be corrupted" warning

**Solution:**
The container verification may be too strict. Check the file manually:

```bash
file /tmp/test-cask-mirror/abc123.dmg
hdiutil verify /tmp/test-cask-mirror/abc123.dmg  # For DMG files
```

If the file is actually fine, adjust the verification logic.

### Issue: Downloads timeout

**Solution:**
Increase the timeout or retry count:

```ruby
success = DownloadHelpers.fetch_with_retry(downloader, max_retries: 5)
```

### Issue: Out of disk space

**Solution:**
Casks are large! Check available space:

```bash
df -h /tmp
```

You need at least 100GB for a full cask mirror.

## Commit Message

When done:

```bash
git add mirror/bin/brew-mirror mirror/lib/container_helpers.rb mirror/lib/download_helpers.rb
git commit -m "Task 2.2: Enhance cask download handling

- Add support for multiple container formats (DMG, PKG, ZIP, etc.)
- Implement download retry logic with exponential backoff
- Add container file verification
- Show download progress and size information
- Handle multiple URLs per cask
- Add cask mirror statistics
- Gracefully handle download failures"
```

## Next Steps

Proceed to **Task 2.3: Update brew-offline-install for Casks**
