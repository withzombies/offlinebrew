#!/usr/bin/env brew ruby
# frozen_string_literal: true

# Discovery script for Homebrew download strategies
# This helps identify which strategies are available in the current Homebrew installation

puts "Discovering Download Strategies..."
puts "=" * 70
puts ""

# Get all download strategy classes
strategies = ObjectSpace.each_object(Class).select do |klass|
  klass.name && klass.name.end_with?("DownloadStrategy")
end

puts "Found #{strategies.count} download strategies in Homebrew:\n\n"

strategies.sort_by(&:name).each do |strategy|
  # Try to get the parent class
  parent = strategy.superclass
  parent_name = parent.name if parent && parent.name

  puts "  - #{strategy.name}"
  puts "    Parent: #{parent_name}" if parent_name
end

puts "\n" + "=" * 70
puts "Currently supported in offlinebrew:"
puts "=" * 70

current = [
  "CurlDownloadStrategy",
  "CurlApacheMirrorDownloadStrategy",
  "NoUnzipCurlDownloadStrategy",
  "GitDownloadStrategy",
  "GitHubGitDownloadStrategy",
]

current.each { |s| puts "  ✓ #{s}" }

puts "\n" + "=" * 70
puts "Strategies NOT yet supported:"
puts "=" * 70

unsupported = strategies.reject { |strategy| current.include?(strategy.name) }
unsupported.sort_by(&:name).each do |strategy|
  puts "  ? #{strategy.name}"
end

puts "\n" + "=" * 70
puts "Analysis:"
puts "=" * 70

# Categorize strategies
curl_based = strategies.select { |s| s.name.include?("Curl") }.sort_by(&:name)
git_based = strategies.select { |s| s.name.include?("Git") }.sort_by(&:name)
scm_other = strategies.select { |s|
  s.name =~ /(Subversion|SVN|CVS|Mercurial|Bazaar|Fossil|Hg)/i
}.sort_by(&:name)

puts "\nCurl-based strategies (HTTP/HTTPS):"
curl_based.each { |s| puts "  - #{s.name}" }

puts "\nGit-based strategies:"
git_based.each { |s| puts "  - #{s.name}" }

puts "\nOther SCM strategies:"
scm_other.each { |s| puts "  - #{s.name}" }

puts "\nOther:"
other = strategies - curl_based - git_based - scm_other
other.sort_by(&:name).each { |s| puts "  - #{s.name}" }

puts "\n" + "=" * 70
puts "Recommendations:"
puts "=" * 70

newly_supported = curl_based.select { |s| !current.include?(s.name) }
if newly_supported.any?
  puts "\n✓ Consider adding these Curl-based strategies (likely easy to support):"
  newly_supported.each { |s| puts "  - #{s.name}" }
end

git_newly = git_based.select { |s| !current.include?(s.name) }
if git_newly.any?
  puts "\n✓ Consider adding these Git-based strategies:"
  git_newly.each { |s| puts "  - #{s.name}" }
end

if scm_other.any?
  puts "\n⚠ These SCM strategies may be difficult to support:"
  scm_other.each { |s| puts "  - #{s.name} (requires external tools)" }
end

puts ""
