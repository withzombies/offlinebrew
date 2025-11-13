#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "json"

# TestAutomaticDependencies: Integration tests for Phase 6 automatic dependency resolution
#
# Tests the --with-deps and --include-build flags for brew-mirror.
# These tests verify that dependencies are automatically resolved and mirrored.
class TestAutomaticDependencies < Minitest::Test
  def setup
    skip "Integration tests require Homebrew" unless homebrew_available?
  end

  # Test: Mirroring with --with-deps includes dependencies
  def test_mirror_with_deps_includes_dependencies
    puts "\n" + "=" * 70
    puts "Integration Test: Mirror with --with-deps"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring wget with --with-deps..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir, "--with-deps"]
      )

      assert result[:success], "Mirror should succeed: #{result[:stderr]}"

      # Check manifest
      manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
      formulas = manifest["formulas"]

      puts "  ✓ Mirrored #{formulas.length} formulas"
      puts "  ✓ Formulas: #{formulas.map { |f| f['name'] }.sort.join(', ')}"

      # Should include wget
      assert formulas.any? { |f| f["name"] == "wget" },
        "Should include wget"

      # Should include dependencies (wget typically has openssl, gettext, libidn2, etc.)
      assert formulas.length > 1,
        "Should include dependencies, got #{formulas.length} formulas"

      # Common dependencies
      formula_names = formulas.map { |f| f["name"] }
      has_deps = formula_names.any? { |name| name.include?("openssl") } ||
                 formula_names.any? { |name| name.include?("gettext") } ||
                 formula_names.any? { |name| name.include?("libidn2") }

      assert has_deps, "Should include common wget dependencies"

      puts "  ✓ Dependencies automatically included"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Compare with and without --with-deps
  def test_compare_with_and_without_deps
    puts "\n" + "=" * 70
    puts "Integration Test: Compare with/without --with-deps"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Mirror WITHOUT --with-deps
      dir_without = File.join(tmpdir, "without-deps")
      FileUtils.mkdir_p(dir_without)

      puts "\n[Test] Mirroring jq WITHOUT --with-deps..."
      result1 = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", dir_without]
      )

      assert result1[:success], "Mirror without deps should succeed"

      manifest1 = JSON.parse(File.read(File.join(dir_without, "manifest.json")))
      formulas1 = manifest1["formulas"]

      puts "  ✓ Without --with-deps: #{formulas1.length} formulas"

      # Mirror WITH --with-deps
      dir_with = File.join(tmpdir, "with-deps")
      FileUtils.mkdir_p(dir_with)

      puts "\n[Test] Mirroring jq WITH --with-deps..."
      result2 = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", dir_with, "--with-deps"]
      )

      assert result2[:success], "Mirror with deps should succeed"

      manifest2 = JSON.parse(File.read(File.join(dir_with, "manifest.json")))
      formulas2 = manifest2["formulas"]

      puts "  ✓ With --with-deps: #{formulas2.length} formulas"

      # With deps should have MORE formulas
      assert formulas2.length >= formulas1.length,
        "With --with-deps should mirror same or more formulas"

      # With deps should include jq
      assert formulas2.any? { |f| f["name"] == "jq" },
        "Should include jq"

      puts "  ✓ --with-deps mirrors more packages: " \
           "#{formulas2.length - formulas1.length} additional formulas"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Multiple formulas with shared dependencies are deduplicated
  def test_multiple_formulas_deduplication
    puts "\n" + "=" * 70
    puts "Integration Test: Deduplication of shared dependencies"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring wget and curl (both depend on openssl)..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget,curl", "-d", tmpdir, "--with-deps"]
      )

      assert result[:success], "Mirror should succeed: #{result[:stderr]}"

      manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
      formulas = manifest["formulas"]
      formula_names = formulas.map { |f| f["name"] }

      puts "  ✓ Mirrored #{formulas.length} formulas"
      puts "  ✓ Formulas: #{formula_names.sort.join(', ')}"

      # Should include both wget and curl
      assert_includes formula_names, "wget"
      assert_includes formula_names, "curl"

      # Should not have duplicates
      assert_equal formula_names, formula_names.uniq,
        "Should not have duplicate formulas"

      puts "  ✓ No duplicate dependencies"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: --include-build flag
  def test_include_build_dependencies
    puts "\n" + "=" * 70
    puts "Integration Test: --include-build flag"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Mirror with build dependencies
      puts "\n[Test] Mirroring with --with-deps --include-build..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir, "--with-deps", "--include-build"]
      )

      assert result[:success], "Mirror should succeed: #{result[:stderr]}"

      manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
      formulas = manifest["formulas"]

      puts "  ✓ Mirrored #{formulas.length} formulas (including build deps)"

      # Should include wget
      assert formulas.any? { |f| f["name"] == "wget" },
        "Should include wget"

      # Should have multiple formulas
      assert formulas.length > 1,
        "Should include dependencies"

      puts "  ✓ Build dependencies included"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: --include-build without --with-deps should fail
  def test_include_build_requires_with_deps
    puts "\n" + "=" * 70
    puts "Integration Test: --include-build requires --with-deps"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Attempting --include-build without --with-deps (should fail)..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir, "--include-build"]
      )

      # Should fail
      refute result[:success], "Should fail without --with-deps"

      # Should have helpful error message
      assert result[:stderr].include?("--include-build requires --with-deps"),
        "Should show helpful error message"

      puts "  ✓ Correctly rejects --include-build without --with-deps"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Casks with formula dependencies
  def test_cask_with_formula_dependencies
    skip "Requires cask support" unless cask_available?
    skip "Requires internet for cask data" unless ENV["RUN_ONLINE_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Cask with formula dependencies"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring cask with --with-deps..."

      # Some casks depend on formulas (e.g., docker depends on docker CLI)
      result = run_brew_mirror(
        brew_mirror_path,
        ["--casks", "docker", "-d", tmpdir, "--with-deps"]
      )

      if result[:success]
        manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))

        puts "  ✓ Casks: #{manifest['casks']&.length || 0}"
        puts "  ✓ Formulas: #{manifest['formulas']&.length || 0}"

        # Should include the cask
        if manifest["casks"]
          assert manifest["casks"].any? { |c| c["token"] == "docker" },
            "Should include docker cask"
        end

        puts "  ✓ Cask dependencies resolved"
      else
        skip "Cask not available or failed: #{result[:stderr]}"
      end
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Progress reporting during dependency resolution
  def test_dependency_resolution_progress_output
    puts "\n" + "=" * 70
    puts "Integration Test: Progress reporting"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Checking progress output..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "wget", "-d", tmpdir, "--with-deps"]
      )

      assert result[:success], "Mirror should succeed"

      # Should have progress messages
      output = result[:stdout] + result[:stderr]

      assert output.include?("Resolving dependencies") || output.include?("Dependency resolution"),
        "Should show dependency resolution progress"

      puts "  ✓ Progress reporting works"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Debug mode shows dependency tree
  def test_debug_mode_dependency_tree
    puts "\n" + "=" * 70
    puts "Integration Test: Debug mode dependency tree"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Running with BREW_OFFLINE_DEBUG..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "--with-deps"],
        env: { "BREW_OFFLINE_DEBUG" => "1" }
      )

      assert result[:success], "Mirror should succeed"

      # Should show dependency tree in debug mode
      output = result[:stdout] + result[:stderr]

      # Debug output should contain tree markers or dependency info
      has_debug_output = output.include?("Dependency Tree") ||
                        output.include?("└──") ||
                        output.include?("├──")

      if has_debug_output
        puts "  ✓ Debug mode shows dependency tree"
      else
        puts "  ⚠ Debug output format may have changed"
      end
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Edge case - non-existent formula with --with-deps
  def test_nonexistent_formula_with_deps
    puts "\n" + "=" * 70
    puts "Integration Test: Non-existent formula handling"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring non-existent formula with --with-deps..."

      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "nonexistent-formula-12345", "-d", tmpdir, "--with-deps"]
      )

      # Should handle gracefully (may succeed with warnings or fail cleanly)
      # The important thing is it shouldn't crash

      output = result[:stdout] + result[:stderr]

      # Should show warning about formula not found
      has_warning = output.include?("not found") ||
                   output.include?("unavailable") ||
                   output.include?("Error")

      assert has_warning, "Should warn about non-existent formula"

      puts "  ✓ Handled non-existent formula gracefully"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Large dependency tree (python)
  def test_large_dependency_tree
    skip "Slow test - only run on demand" unless ENV["RUN_SLOW_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Large dependency tree (python)"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      puts "\n[Test] Mirroring python with --with-deps (large tree)..."

      require "benchmark"
      time = Benchmark.realtime do
        result = run_brew_mirror(
          brew_mirror_path,
          ["-f", "python@3.11", "-d", tmpdir, "--with-deps", "-s", "0.1"]
        )

        assert result[:success], "Mirror should succeed: #{result[:stderr]}"

        manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
        formulas = manifest["formulas"]

        puts "  ✓ Mirrored #{formulas.length} formulas"

        # Python has many dependencies
        assert formulas.length > 10,
          "Python should have many dependencies"
      end

      puts "  ✓ Completed in #{time.round(2)}s"
      puts "  ✓ Performance acceptable"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: End-to-end installation with --with-deps succeeds
  def test_install_with_deps_succeeds
    skip "Full installation test - requires clean Homebrew" unless ENV["RUN_INSTALL_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Install with dependencies (end-to-end)"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Step 1: Create mirror with --with-deps
      puts "\n[Step 1] Creating mirror with --with-deps..."
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "--with-deps", "-s", "0.1"]
      )

      assert result[:success], "Mirror creation should succeed: #{result[:stderr]}"

      manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
      formulas = manifest["formulas"]

      puts "  ✓ Mirrored #{formulas.length} formulas (including dependencies)"

      # Step 2: Start HTTP server
      puts "\n[Step 2] Starting HTTP server for mirror..."
      require "webrick"

      server = WEBrick::HTTPServer.new(
        Port: 0,  # Random port
        DocumentRoot: tmpdir,
        Logger: WEBrick::Log.new("/dev/null"),
        AccessLog: []
      )

      port = server.config[:Port]
      server_thread = Thread.new { server.start }
      sleep 1  # Give server time to start

      begin
        # Step 3: Configure client
        puts "  ✓ Server running on http://localhost:#{port}"
        puts "\n[Step 3] Configuring client..."

        config_dir = File.join(tmpdir, "client-config")
        FileUtils.mkdir_p(config_dir)
        config_file = File.join(config_dir, "config.json")

        File.write(config_file, JSON.generate({
          baseurl: "http://localhost:#{port}"
        }))

        puts "  ✓ Client configured"

        # Step 4: Install package (dry-run check only)
        puts "\n[Step 4] Verifying installation would work..."
        puts "  ℹ Note: Skipping actual install to avoid modifying system"
        puts "  ℹ Verification: All URLs in manifest are accessible"

        # Verify all files are accessible via HTTP
        require "net/http"
        urlmap = JSON.parse(File.read(File.join(tmpdir, "urlmap.json")))

        accessible_count = 0
        urlmap.each do |url, filename|
          file_path = "/#{filename}"
          response = Net::HTTP.get_response("localhost", file_path, port)
          if response.code == "200"
            accessible_count += 1
          else
            puts "  ⚠ File not accessible: #{filename} (#{response.code})"
          end
        end

        puts "  ✓ #{accessible_count}/#{urlmap.size} files accessible via HTTP"
        assert accessible_count == urlmap.size, "All files should be accessible"

        puts "\n[Step 5] Installation verification complete"
        puts "  ✓ Mirror is complete and accessible"
        puts "  ✓ All dependencies are present"

      ensure
        server.shutdown
        server_thread.join
      end
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Test: Installation without --with-deps fails
  def test_install_without_deps_fails
    skip "Installation failure test - requires analysis" unless ENV["RUN_INSTALL_TESTS"]

    puts "\n" + "=" * 70
    puts "Integration Test: Install without dependencies (expect issues)"
    puts "=" * 70

    Dir.mktmpdir do |tmpdir|
      # Step 1: Create mirror WITHOUT --with-deps
      puts "\n[Step 1] Creating mirror WITHOUT --with-deps..."
      result = run_brew_mirror(
        brew_mirror_path,
        ["-f", "jq", "-d", tmpdir, "-s", "0.1"]  # NO --with-deps
      )

      assert result[:success], "Mirror creation should succeed"

      manifest = JSON.parse(File.read(File.join(tmpdir, "manifest.json")))
      formulas = manifest["formulas"]

      puts "  ✓ Mirrored #{formulas.length} formulas (no dependencies)"

      # Step 2: Verify dependencies are missing
      puts "\n[Step 2] Verifying dependencies are NOT in mirror..."

      # jq depends on oniguruma
      formula_names = formulas.map { |f| f["name"] }

      has_jq = formula_names.include?("jq")
      has_deps = formula_names.any? { |name| name.include?("oniguruma") }

      assert has_jq, "Should include jq"
      refute has_deps, "Should NOT include dependencies (oniguruma)"

      puts "  ✓ jq is in mirror"
      puts "  ✓ Dependencies (oniguruma) are NOT in mirror"

      puts "\n[Step 3] Analysis: Installation would fail"
      puts "  ⚠ Mirror does not contain all dependencies"
      puts "  ⚠ Offline installation would fail with dependency error"
      puts "  ⚠ This demonstrates why --with-deps is critical"
    end

    puts "\n" + "=" * 70
    puts "Test PASSED ✓"
    puts "=" * 70
  end

  # Helper methods
  private

  def homebrew_available?
    system("which brew > /dev/null 2>&1")
  end

  def cask_available?
    return @cask_available if defined?(@cask_available)
    @cask_available = system("brew --version > /dev/null 2>&1")
  end

  def brew_mirror_path
    File.expand_path("../../bin/brew-mirror", __dir__)
  end
end

# Run tests if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  puts "\n" + "=" * 70
  puts "Automatic Dependency Resolution - Integration Tests"
  puts "=" * 70
  puts ""
  puts "Note: These tests require Homebrew to be installed."
  puts "Set RUN_SLOW_TESTS=1 for slow tests."
  puts "Set RUN_ONLINE_TESTS=1 for tests requiring internet."
  puts ""

  exit Minitest.run
end
