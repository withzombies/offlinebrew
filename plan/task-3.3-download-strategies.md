# Task 3.3: Add Additional Download Strategies

## Objective

Discover and add support for any new download strategies that have been added to Homebrew since 2019.

## Prerequisites

- Task 1.3 completed (API compatibility test)

## Implementation Steps

### Step 1: Run Discovery Script

Create `mirror/test/discover_strategies.rb`:

```ruby
#!/usr/bin/env brew ruby
# frozen_string_literal: true

puts "Discovering Download Strategies..."
puts "=" * 50

# Get all download strategy classes
strategies = ObjectSpace.each_object(Class).select do |klass|
  klass.name && klass.name.end_with?("DownloadStrategy")
end

puts "Found #{strategies.count} download strategies:\n\n"

strategies.sort_by(&:name).each do |strategy|
  puts "  - #{strategy.name}"
end

puts "\nCurrently supported in offlinebrew:"
current = [
  "CurlDownloadStrategy",
  "CurlApacheMirrorDownloadStrategy",
  "NoUnzipCurlDownloadStrategy",
  "GitDownloadStrategy",
  "GitHubGitDownloadStrategy",
]

current.each { |s| puts "  ✓ #{s}" }

puts "\nNot yet supported:"
strategies.each do |strategy|
  unless current.include?(strategy.name)
    puts "  ? #{strategy.name}"
  end
end
```

Run it:
```bash
brew ruby mirror/test/discover_strategies.rb
```

### Step 2: Add New Strategies to brew-mirror

Edit `mirror/bin/brew-mirror`:

**Update BREW_OFFLINE_DOWNLOAD_STRATEGIES based on discovery:**

```ruby
BREW_OFFLINE_DOWNLOAD_STRATEGIES = [
  CurlDownloadStrategy,
  CurlApacheMirrorDownloadStrategy,
  NoUnzipCurlDownloadStrategy,
  GitDownloadStrategy,
  GitHubGitDownloadStrategy,
  # Add newly discovered strategies:
  # (Only add if they exist in your Homebrew version)
].compact.select { |s| defined?(s) }.freeze
```

### Step 3: Test Each New Strategy

For each new strategy, determine:
1. How it downloads (HTTP, Git, other?)
2. Whether it needs special handling
3. Update `sensible_identifier` if needed

### Step 4: Document Unsupported Strategies

If any strategies can't be supported (e.g., SVN), document why:

**In `mirror/docs/DOWNLOAD_STRATEGIES.md`:**

```markdown
# Download Strategy Support

## Supported

- CurlDownloadStrategy - Standard HTTP(S) downloads
- CurlApacheMirrorDownloadStrategy - Apache mirror downloads
- NoUnzipCurlDownloadStrategy - Downloads without auto-unzip
- GitDownloadStrategy - Git repository clones
- GitHubGitDownloadStrategy - GitHub repository clones

## Unsupported

- SubversionDownloadStrategy - SVN repositories (rare, requires svn binary)
- CVSDownloadStrategy - CVS repositories (obsolete)
- FossilDownloadStrategy - Fossil SCM (very rare)

## Adding Support

To add a new strategy:
1. Add to BREW_OFFLINE_DOWNLOAD_STRATEGIES array
2. Update sensible_identifier if needed
3. Test with a formula that uses it
```

## Testing

```bash
# Test that new strategies don't break existing functionality
brew ruby mirror/bin/brew-mirror -d /tmp/test -f wget,jq,curl -s 1
```

## Acceptance Criteria

✅ Done when:
1. All available download strategies discovered
2. Common strategies added to supported list
3. Unsupported strategies documented
4. No errors when mirroring common formulae

## Commit Message

```bash
git add mirror/bin/brew-mirror mirror/test/discover_strategies.rb mirror/docs/DOWNLOAD_STRATEGIES.md
git commit -m "Task 3.3: Update supported download strategies

- Add strategy discovery script
- Document supported and unsupported strategies
- Update BREW_OFFLINE_DOWNLOAD_STRATEGIES list
- Add compatibility checks"
```

## Next Steps

Proceed to **Task 4.1: Create Verification System** (Phase 4)
