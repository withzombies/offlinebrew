# Task 4.2: Generate Mirror Manifest

## Objective

Create a human-readable manifest file documenting what's in the mirror.

## Prerequisites

- Task 4.1 completed

## Implementation Steps

### Step 1: Add Manifest Generation to brew-mirror

Edit `mirror/bin/brew-mirror`:

**At the end, before writing urlmap:**

```ruby
# Generate manifest
manifest = {
  created_at: Time.now.iso8601,
  taps: {},
  statistics: {
    total_formulae: 0,
    total_casks: 0,
    total_files: urlmap.count,
    total_size_bytes: 0,
  },
  formulae: [],
  casks: [],
}

# Calculate size
manifest[:statistics][:total_size_bytes] = Dir.glob("#{options[:directory]}/*")
  .map { |f| File.size(f) rescue 0 }
  .sum

# Add tap info
config[:taps].each do |tap_name, tap_info|
  manifest[:taps][tap_name] = tap_info
end

# Write manifest
manifest_file = File.join(options[:directory], "manifest.json")
File.write manifest_file, JSON.pretty_generate(manifest)
ohai "Manifest written to: manifest.json"
```

### Step 2: Track Mirrored Packages

**In the formula loop, add to manifest:**

```ruby
options[:iterator].each do |formula|
  # ... existing code ...

  manifest[:formulae] << {
    name: formula.name,
    version: formula.version.to_s,
    url: formula.stable.url,
    tap: formula.tap.name,
  }
  manifest[:statistics][:total_formulae] += 1
end
```

**In the cask loop:**

```ruby
cask_iterator.each do |cask|
  # ... existing code ...

  manifest[:casks] << {
    token: cask.token,
    name: cask.name.first,
    version: cask.version.to_s,
    url: cask.url.to_s,
  }
  manifest[:statistics][:total_casks] += 1
end
```

### Step 3: Create Human-Readable Report

**Add option for HTML report:**

```ruby
def generate_html_report(manifest, output_file)
  html = <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Offlinebrew Mirror Manifest</title>
      <style>
        body { font-family: sans-serif; margin: 40px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #f2f2f2; }
        .stats { background: #f9f9f9; padding: 20px; margin: 20px 0; }
      </style>
    </head>
    <body>
      <h1>Offlinebrew Mirror Manifest</h1>

      <div class="stats">
        <h2>Statistics</h2>
        <p><strong>Created:</strong> #{manifest[:created_at]}</p>
        <p><strong>Formulae:</strong> #{manifest[:statistics][:total_formulae]}</p>
        <p><strong>Casks:</strong> #{manifest[:statistics][:total_casks]}</p>
        <p><strong>Total Files:</strong> #{manifest[:statistics][:total_files]}</p>
        <p><strong>Total Size:</strong> #{(manifest[:statistics][:total_size_bytes] / 1024.0 / 1024.0 / 1024.0).round(2)} GB</p>
      </div>

      <h2>Taps</h2>
      <table>
        <tr><th>Tap</th><th>Commit</th><th>Type</th></tr>
  HTML

  manifest[:taps].each do |tap, info|
    html += "    <tr><td>#{tap}</td><td>#{info["commit"][0..7]}</td><td>#{info["type"]}</td></tr>\n"
  end

  html += <<~HTML
      </table>

      <h2>Formulae</h2>
      <table>
        <tr><th>Name</th><th>Version</th><th>Tap</th></tr>
  HTML

  manifest[:formulae].each do |formula|
    html += "    <tr><td>#{formula[:name]}</td><td>#{formula[:version]}</td><td>#{formula[:tap]}</td></tr>\n"
  end

  html += <<~HTML
      </table>

      <h2>Casks</h2>
      <table>
        <tr><th>Token</th><th>Name</th><th>Version</th></tr>
  HTML

  manifest[:casks].each do |cask|
    html += "    <tr><td>#{cask[:token]}</td><td>#{cask[:name]}</td><td>#{cask[:version]}</td></tr>\n"
  end

  html += <<~HTML
      </table>
    </body>
    </html>
  HTML

  File.write(output_file, html)
end

# Generate HTML report
html_file = File.join(options[:directory], "manifest.html")
generate_html_report(manifest, html_file)
ohai "HTML report: manifest.html"
```

## Testing

```bash
brew ruby mirror/bin/brew-mirror -d /tmp/test -f wget --casks firefox -s 1

# Check manifest
cat /tmp/test/manifest.json

# Open HTML report
open /tmp/test/manifest.html  # macOS
xdg-open /tmp/test/manifest.html  # Linux
```

## Acceptance Criteria

✅ Done when:
1. manifest.json created with complete info
2. HTML report generated
3. Lists all formulae and casks
4. Shows statistics and tap info
5. Human-readable format

## Commit Message

```bash
git add mirror/bin/brew-mirror
git commit -m "Task 4.2: Add mirror manifest generation

- Generate manifest.json with complete mirror info
- Track all formulae and casks mirrored
- Calculate statistics (size, counts)
- Generate HTML report for easy viewing
- Include tap information and commits"
```

## Next Steps

Proceed to **Task 4.3: Implement Incremental Updates**
