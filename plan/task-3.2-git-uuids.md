# Task 3.2: Fix Git Repository UUID Collision

## Objective

Replace random UUIDs for Git repositories with deterministic identifiers to prevent duplicate mirroring of the same repository.

## Background

Currently, `brew-mirror` uses `SecureRandom.uuid` for Git repositories. This means the same Git repo at the same commit gets different UUIDs on each mirror run, wasting disk space.

**Problem in current code (line 42):**
```ruby
SecureRandom.uuid  # Different every time!
```

## Prerequisites

- Phase 1 completed

## Implementation Steps

### Step 1: Create Deterministic Git Identifier

Edit `mirror/bin/brew-mirror`:

**Find the `sensible_identifier` function (around line 34-46):**

```ruby
def sensible_identifier(strategy, checksum = nil)
  case strategy
  when GitDownloadStrategy, GitHubGitDownloadStrategy
    SecureRandom.uuid  # BAD: Random every time
  else
    checksum.to_s
  end
end
```

**Replace with:**

```ruby
def sensible_identifier(strategy, checksum = nil, url = nil)
  case strategy
  when GitDownloadStrategy, GitHubGitDownloadStrategy
    # Use deterministic identifier based on URL and revision
    # This prevents duplicate mirrors of the same repository
    require "digest"

    # Get the revision/commit being checked out
    revision = if strategy.respond_to?(:resolved_ref)
                 strategy.resolved_ref
               elsif strategy.respond_to?(:ref)
                 strategy.ref || "HEAD"
               else
                 "HEAD"
               end

    # Create deterministic hash: SHA256(url + revision)
    Digest::SHA256.hexdigest("#{url}@#{revision}")
  else
    checksum.to_s
  end
end
```

### Step 2: Update Function Calls

**Find all calls to `sensible_identifier` and add URL parameter:**

Around line 137:
```ruby
resources << MirrorResource.new(formula.stable,
                                sensible_identifier(formula.stable.downloader,
                                                    formula.stable.checksum,
                                                    formula.stable.url),  # Add this
                                formula.stable.downloader,
                                formula.stable.url)
```

Around line 143:
```ruby
resources << MirrorResource.new(res,
                                sensible_identifier(res.downloader,
                                                    res.checksum,
                                                    res.url),  # Add this
                                res.downloader,
                                res.url)
```

Around line 150:
```ruby
resources << MirrorResource.new(patch,
                                sensible_identifier(patch.resource.downloader,
                                                    patch.resource.checksum,
                                                    patch.url),  # Add this
                                patch.resource.downloader,
                                patch.url)
```

### Step 3: Add Git Revision Resolution

Some Git strategies may need to resolve the actual commit:

**Add helper function:**

```ruby
# Resolve the actual Git commit for a repository
# This ensures we get the real commit hash, not just "master" or "HEAD"
def resolve_git_revision(downloader)
  return "HEAD" unless downloader.is_a?(GitDownloadStrategy) ||
                       downloader.is_a?(GitHubGitDownloadStrategy)

  # Try to get the resolved reference
  if downloader.respond_to?(:resolved_ref) && downloader.resolved_ref
    return downloader.resolved_ref
  end

  # Try to get the ref
  if downloader.respond_to?(:ref) && downloader.ref
    return downloader.ref
  end

  # Default
  "HEAD"
end
```

**Use in sensible_identifier:**

```ruby
def sensible_identifier(strategy, checksum = nil, url = nil, downloader = nil)
  case strategy
  when GitDownloadStrategy, GitHubGitDownloadStrategy
    require "digest"

    revision = if downloader
                 resolve_git_revision(downloader)
               else
                 "HEAD"
               end

    Digest::SHA256.hexdigest("#{url}@#{revision}")
  else
    checksum.to_s
  end
end
```

### Step 4: Add Identifier Cache

To track what we've already mirrored:

**At the start of mirroring:**

```ruby
# Load existing identifier cache if it exists
identifier_cache_file = File.join(options[:directory], "identifier_cache.json")
identifier_cache = if File.exist?(identifier_cache_file)
                     JSON.parse(File.read(identifier_cache_file))
                   else
                     {}
                   end
```

**When creating identifiers:**

```ruby
# Check if we've seen this URL+revision before
cache_key = "#{url}@#{revision}"
identifier = if identifier_cache[cache_key]
               identifier_cache[cache_key]
             else
               new_id = Digest::SHA256.hexdigest(cache_key)
               identifier_cache[cache_key] = new_id
               new_id
             end
```

**At the end:**

```ruby
# Write identifier cache
File.write identifier_cache_file, JSON.pretty_generate(identifier_cache)
```

## Testing

### Test 1: Mirror Same Formula Twice

```bash
rm -rf /tmp/git-test-mirror
mkdir /tmp/git-test-mirror

# Mirror once
brew ruby mirror/bin/brew-mirror -d /tmp/git-test-mirror -f vim -s 1

# Count Git repos
find /tmp/git-test-mirror -name "*.git" | wc -l

# Mirror again (should not duplicate)
brew ruby mirror/bin/brew-mirror -d /tmp/git-test-mirror -f vim -s 1

# Count again - should be same
find /tmp/git-test-mirror -name "*.git" | wc -l
```

**Expected:** Same count both times.

### Test 2: Check Identifier Cache

```bash
cat /tmp/git-test-mirror/identifier_cache.json
```

**Expected:** JSON mapping of URL@revision -> identifier

### Test 3: Verify Deterministic IDs

Run this Ruby snippet:

```ruby
require "digest"

url = "https://github.com/vim/vim.git"
revision = "v9.0.0000"

id1 = Digest::SHA256.hexdigest("#{url}@#{revision}")
id2 = Digest::SHA256.hexdigest("#{url}@#{revision}")

puts "ID 1: #{id1}"
puts "ID 2: #{id2}"
puts "Match: #{id1 == id2}"
```

**Expected:** Match: true

## Acceptance Criteria

✅ Done when:
1. Git repos use deterministic identifiers
2. Same repo at same commit gets same ID
3. identifier_cache.json tracks all Git identifiers
4. No duplicate Git repos in mirror
5. Mirror runs are idempotent (can run twice safely)

## Commit Message

```bash
git add mirror/bin/brew-mirror
git commit -m "Task 3.2: Use deterministic identifiers for Git repositories

- Replace SecureRandom.uuid with SHA256(url@revision)
- Add resolve_git_revision helper function
- Create identifier_cache.json for tracking
- Prevent duplicate Git repo mirrors
- Make mirror operations idempotent"
```

## Next Steps

Proceed to **Task 3.3: Add Additional Download Strategies**
