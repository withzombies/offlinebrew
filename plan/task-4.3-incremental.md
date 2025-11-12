# Task 4.3: Implement Incremental Updates

## Objective

Enable updating an existing mirror without re-downloading unchanged packages.

## Prerequisites

- Tasks 4.1 and 4.2 completed

## Implementation Steps

### Step 1: Add Update Mode

Edit `mirror/bin/brew-mirror`:

**Add CLI option:**

```ruby
parser.on "--update", "update existing mirror (skip unchanged packages)" do
  options[:update_mode] = true
end
```

### Step 2: Load Existing Manifest

**Before starting mirror:**

```ruby
existing_manifest = if options[:update_mode]
                      manifest_file = File.join(options[:directory], "manifest.json")
                      if File.exist?(manifest_file)
                        JSON.parse(File.read(manifest_file))
                      else
                        opoo "No existing manifest found, performing full mirror"
                        nil
                      end
                    end
```

### Step 3: Skip Unchanged Packages

**In formula/cask loops:**

```ruby
# Check if package already mirrored
if existing_manifest && options[:update_mode]
  already_mirrored = existing_manifest["formulae"].any? do |f|
    f["name"] == formula.name && f["version"] == formula.version.to_s
  end

  if already_mirrored
    ohai "#{formula.name} already in mirror, skipping"
    next
  end
end
```

### Step 4: Prune Old Versions (Optional)

**Add --prune option:**

```ruby
parser.on "--prune", "remove old versions when updating" do
  options[:prune_old] = true
end
```

**At the end:**

```ruby
if options[:prune_old] && existing_manifest
  # Find packages in old manifest but not in new
  old_formulae = existing_manifest["formulae"].map { |f| f["name"] }
  new_formulae = manifest[:formulae].map { |f| f[:name] }
  removed = old_formulae - new_formulae

  removed.each do |name|
    ohai "Removing old formula: #{name}"
    # Find and remove files (implementation depends on tracking)
  end
end
```

## Testing

```bash
# Create initial mirror
brew ruby mirror/bin/brew-mirror -d /tmp/incremental -f wget -s 1

# Update it (should skip wget if unchanged)
brew ruby mirror/bin/brew-mirror -d /tmp/incremental -f wget,jq --update -s 1
```

**Expected:** wget skipped, jq downloaded

## Acceptance Criteria

✅ Done when:
1. --update mode works
2. Skips unchanged packages
3. Only downloads new/changed packages
4. --prune removes old versions
5. Update is faster than full mirror

## Commit Message

```bash
git add mirror/bin/brew-mirror
git commit -m "Task 4.3: Add incremental mirror update support

- Add --update mode to skip unchanged packages
- Compare against existing manifest
- Add --prune option to remove old versions
- Significantly faster for mirror updates
- Preserve existing downloads when possible"
```

## Next Steps

Proceed to **Task 5.1: Create Test Scripts** (Phase 5 - Final phase!)
