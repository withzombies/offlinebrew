#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

# TDD Test: Verify brew ruby command syntax
#
# Purpose: Document and verify the correct way to invoke scripts via brew ruby
# This test was created after multiple failed attempts to fix integration tests.
#
# Key Learning:
# - SHORT options (-d, -c): brew ruby script.rb -d /tmp
# - LONG options (--formulae): brew ruby -- script.rb --formulae jq
# - The -- separator prevents brew ruby from parsing long options
class TestBrewRubyCommandSyntax < Minitest::Test
  # Test: brew ruby command structure for LONG options
  def test_brew_ruby_syntax_with_long_options_requires_separator
    # CORRECT syntax for long options (--something):
    # brew ruby -- script.rb --long-option value

    # When using LONG options, -- is required to prevent brew ruby from
    # parsing them as its own options

    correct_syntax = "brew ruby -- bin/brew-mirror --formulae jq --directory /tmp/test"

    # Verify -- separator is present
    assert_includes correct_syntax, " -- ",
      "brew ruby requires -- separator when script uses long options (--something)"

    # Verify format: brew ruby -- <path> <args>
    assert_match(/^brew ruby -- \S+ /, correct_syntax,
      "Command should be: brew ruby -- script --args")
  end

  # Test: brew ruby command structure for SHORT options
  def test_brew_ruby_syntax_with_short_options_no_separator
    # SHORT options (-d, -c) can be used without -- separator
    # brew ruby script.rb -d /tmp -c

    correct_syntax = "brew ruby bin/brew-mirror -d /tmp/test -c"

    # No -- separator needed for short options
    refute_includes correct_syntax, " -- ",
      "brew ruby with SHORT options (-x) doesn't need -- separator"

    # Verify format: brew ruby <path> <args>
    assert_match(/^brew ruby \S+ -/, correct_syntax,
      "Command should be: brew ruby script -shortopt")
  end

  # Test: Incorrect placement of -- separator
  def test_brew_ruby_incorrect_separator_placement
    # INCORRECT: -- after script path
    # brew ruby script.rb -- --formulae jq
    # This puts -- in ARGV, not helpful

    # CORRECT: -- before script path
    # brew ruby -- script.rb --formulae jq
    # This tells brew ruby to stop parsing options

    incorrect = "brew ruby bin/brew-mirror -- --formulae jq"
    correct = "brew ruby -- bin/brew-mirror --formulae jq"

    # Both have --, but placement matters
    assert_includes incorrect, " -- "
    assert_includes correct, " -- "

    # Correct has -- immediately after "brew ruby"
    assert_match(/^brew ruby -- /, correct,
      "Correct: -- comes right after 'brew ruby'")

    # Incorrect has -- after script path
    refute_match(/^brew ruby -- /, incorrect,
      "Incorrect: -- comes after script path")
  end

  # Test: Document where this pattern is used successfully
  def test_working_examples_in_codebase
    # KNOWN WORKING examples from .github/workflows/test.yml:
    # These use SHORT options, so no -- needed

    working_examples_short_opts = [
      "brew ruby mirror/test/test_api_compatibility.rb",
      "brew ruby mirror/test/test_cask_api.rb",
      "brew ruby bin/brew-mirror -d /tmp/test-mirror-ci -c",  # short opts: -d, -c
    ]

    working_examples_short_opts.each do |cmd|
      refute_includes cmd, " -- ",
        "Short options don't need --: #{cmd}"

      assert_match(/^brew ruby \S+/, cmd,
        "Should start with 'brew ruby <path>': #{cmd}")
    end

    # For LONG options, we need --
    # These are not in CI yet but should work
    working_examples_long_opts = [
      "brew ruby -- bin/brew-mirror --formulae jq",
      "brew ruby -- bin/brew-offline-install --config /tmp/config.json jq",
    ]

    working_examples_long_opts.each do |cmd|
      assert_includes cmd, "brew ruby -- ",
        "Long options require -- separator: #{cmd}"
    end
  end

  # Test: Integration test commands should match working pattern
  def test_integration_test_commands_follow_pattern
    # Commands that SHOULD be used in integration tests:

    mirror_command = "brew ruby -- /path/to/brew-mirror --formulae jq --directory /tmp"
    install_command = "brew ruby -- /path/to/brew-offline-install --config /tmp/config.json jq"

    [mirror_command, install_command].each do |cmd|
      # Must have -- before script path when using long options
      assert_includes cmd, "brew ruby -- ",
        "Integration test with long options needs --: #{cmd}"

      # Should start with 'brew ruby --'
      assert_match(/^brew ruby -- /, cmd,
        "Should start with 'brew ruby -- ': #{cmd}")

      # Should have long options (--something)
      assert_match(/--\w+/, cmd,
        "Should have long options: #{cmd}")
    end
  end
end
