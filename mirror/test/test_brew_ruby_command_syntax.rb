#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

# TDD Test: Document correct script invocation method
#
# Purpose: Document the CORRECT way to invoke offlinebrew scripts
# This test was created after multiple failed attempts with `brew ruby`.
#
# KEY DISCOVERY:
# Scripts with shebang `#!/usr/bin/env brew ruby` should be executed DIRECTLY:
#   CORRECT: ./bin/brew-mirror -f jq -d /tmp
#   WRONG:   brew ruby bin/brew-mirror -f jq -d /tmp
#
# The shebang tells the system to use `brew ruby` as the interpreter automatically.
# Explicitly calling `brew ruby bin/brew-mirror` double-invokes brew ruby and causes
# option parsing conflicts.
class TestBrewRubyCommandSyntax < Minitest::Test
  # Test: Scripts with brew ruby shebang should be executed directly
  def test_scripts_with_shebang_direct_execution
    # Scripts with shebang `#!/usr/bin/env brew ruby` should be executed DIRECTLY
    # The shebang automatically uses brew ruby as the interpreter

    correct_with_long_options = "./bin/brew-mirror --formulae jq --directory /tmp/test"
    correct_with_short_options = "./bin/brew-mirror -f jq -d /tmp/test"

    # Both forms work because the shebang handles the interpreter
    [correct_with_long_options, correct_with_short_options].each do |cmd|
      refute_includes cmd, "brew ruby",
        "Should NOT include 'brew ruby' - shebang handles it: #{cmd}"

      assert_match(/^\.\/bin\//, cmd,
        "Should start with script path: #{cmd}")
    end
  end

  # Test: Document the WRONG approach (for reference)
  def test_wrong_approach_explicit_brew_ruby_invocation
    # WRONG: Explicitly calling `brew ruby` when script has brew ruby shebang
    # This double-invokes brew ruby and causes option parsing conflicts

    wrong_examples = [
      "brew ruby bin/brew-mirror -f jq",           # Causes: "Error: invalid option: -f"
      "brew ruby bin/brew-mirror --formulae jq",   # Causes: "Error: invalid option: --formulae"
      "brew ruby -- bin/brew-mirror --formulae jq", # Still wrong, double-invokes
    ]

    # Document these as incorrect patterns
    wrong_examples.each do |cmd|
      assert_includes cmd, "brew ruby",
        "These examples show WRONG approach: #{cmd}"
    end
  end

  # Test: When to use `brew ruby` vs direct execution
  def test_when_to_use_brew_ruby_vs_direct
    # Use `brew ruby` ONLY when:
    # 1. Running a script that does NOT have `#!/usr/bin/env brew ruby` shebang
    # 2. Running a one-liner: brew ruby -e "puts Formula['jq'].version"

    # For test scripts without brew ruby shebang:
    test_script_command = "brew ruby mirror/test/test_api_compatibility.rb"
    assert_includes test_script_command, "brew ruby",
      "Test scripts without brew ruby shebang need explicit 'brew ruby'"

    # For executables WITH brew ruby shebang (bin/brew-mirror, bin/brew-offline-install):
    executable_command = "./bin/brew-mirror -f jq -d /tmp"
    refute_includes executable_command, "brew ruby",
      "Executables with brew ruby shebang execute directly"
  end

  # Test: Integration test should use direct execution
  def test_integration_test_pattern
    # Integration tests should execute scripts directly
    # The scripts have `#!/usr/bin/env brew ruby` shebang

    mirror_command = "/path/to/brew-mirror -f jq -d /tmp"
    install_command = "/path/to/brew-offline-install jq"

    [mirror_command, install_command].each do |cmd|
      refute_includes cmd, "brew ruby",
        "Integration test should NOT use 'brew ruby': #{cmd}"
    end
  end
end
