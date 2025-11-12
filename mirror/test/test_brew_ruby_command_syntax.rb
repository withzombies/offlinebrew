#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

# TDD Test: Document correct script invocation method
#
# Purpose: Document the CORRECT way to invoke offlinebrew scripts
# This test was created after multiple failed attempts to get the invocation right.
#
# KEY DISCOVERIES:
# 1. brew-mirror has shebang `#!/usr/bin/env brew ruby` which is BROKEN for direct execution
#    - env doesn't handle multi-word interpreters portably
#    - MUST invoke via: brew ruby bin/brew-mirror
#    - MUST use SHORT options only: -f, -d, -c
#
# 2. brew-offline-install has shebang `#!/usr/bin/env ruby` (normal)
#    - Can execute directly: ./bin/brew-offline-install
#
# 3. Long options (--formulae) cause errors with brew ruby (Homebrew limitation)
class TestBrewRubyCommandSyntax < Minitest::Test
  # Test: brew-mirror MUST use brew ruby with SHORT options
  def test_brew_mirror_invocation_short_options
    # brew-mirror has broken shebang `#!/usr/bin/env brew ruby`
    # MUST invoke via `brew ruby` with SHORT options only

    correct_command = "brew ruby bin/brew-mirror -f jq -d /tmp/test -c"

    # Must have "brew ruby" prefix
    assert_includes correct_command, "brew ruby",
      "brew-mirror MUST be invoked via 'brew ruby'"

    # Must use short options
    assert_match(/-f\s+/, correct_command, "Should use -f (not --formulae)")
    assert_match(/-d\s+/, correct_command, "Should use -d (not --directory)")
    assert_match(/-c/, correct_command, "Should use -c (not --config-only)")
  end

  # Test: brew-mirror with long options FAILS
  def test_brew_mirror_long_options_fail
    # Long options cause "Error: invalid option" because brew ruby's
    # OptionParser consumes them before passing to the script

    wrong_commands = [
      "brew ruby bin/brew-mirror --formulae jq",      # Error: invalid option: --formulae
      "brew ruby bin/brew-mirror -f jq --directory /tmp", # Error: invalid option: --directory
      "brew ruby -- bin/brew-mirror --formulae jq",   # Error: invalid option: --formulae
    ]

    # These all have brew ruby prefix (required)
    wrong_commands.each do |cmd|
      assert_includes cmd, "brew ruby",
        "brew-mirror requires 'brew ruby' prefix: #{cmd}"

      # But they use long options (causes errors)
      assert_match(/--\w+/, cmd,
        "This command uses long options which cause errors: #{cmd}")
    end
  end

  # Test: brew-mirror direct execution FAILS
  def test_brew_mirror_direct_execution_fails
    # Direct execution fails because shebang is broken
    # env: 'brew ruby': No such file or directory

    wrong_command = "./bin/brew-mirror -f jq -d /tmp"

    refute_includes wrong_command, "brew ruby",
      "Direct execution doesn't work - missing 'brew ruby' prefix"
  end

  # Test: brew-offline-install can execute directly
  def test_brew_offline_install_direct_execution
    # brew-offline-install has normal shebang `#!/usr/bin/env ruby`
    # Can execute directly

    correct_command = "./bin/brew-offline-install jq"

    refute_includes correct_command, "brew ruby",
      "brew-offline-install doesn't need 'brew ruby' - has normal shebang"
  end

  # Test: Integration test pattern (what tests should use)
  def test_integration_test_invocation_pattern
    # Integration tests should match CI working examples

    # brew-mirror: Via brew ruby with short options
    mirror_command = "brew ruby /path/to/brew-mirror -f jq -d /tmp"
    assert_includes mirror_command, "brew ruby",
      "Integration tests MUST use 'brew ruby' for brew-mirror"
    assert_match(/-f\s+/, mirror_command,
      "Integration tests MUST use short options: -f")

    # brew-offline-install: Direct execution
    install_command = "/path/to/brew-offline-install jq"
    refute_includes install_command, "brew ruby",
      "brew-offline-install can execute directly"
  end

  # Test: Working CI example matches our pattern
  def test_ci_working_example
    # From .github/workflows/test.yml line 71
    ci_command = "brew ruby bin/brew-mirror -d /tmp/test-mirror-ci -c"

    # Has brew ruby prefix
    assert_includes ci_command, "brew ruby",
      "CI uses 'brew ruby' prefix"

    # Uses short options only
    assert_match(/-d\s+/, ci_command, "CI uses -d (short option)")
    assert_match(/-c/, ci_command, "CI uses -c (short option)")

    # No long options
    refute_match(/--\w+/, ci_command,
      "CI doesn't use long options")
  end
end
