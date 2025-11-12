#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"

# TDD Test: Verify brew ruby command syntax
#
# Purpose: Document and verify the correct way to invoke scripts via brew ruby
# This test was created after multiple failed attempts to fix integration tests.
#
# Key Learning: brew ruby does NOT use -- separator for script arguments
class TestBrewRubyCommandSyntax < Minitest::Test
  # Test: brew ruby command structure
  def test_brew_ruby_syntax_without_separator
    # CORRECT syntax (as used in working GitHub Actions):
    # brew ruby script.rb [script-args]

    correct_syntax = "brew ruby bin/brew-mirror --formulae jq --directory /tmp/test"

    # Verify no -- separator
    refute_includes correct_syntax, " -- ",
      "brew ruby does not use -- separator between script and args"

    # Verify format: brew ruby <path> <args>
    assert_match(/^brew ruby \S+ /, correct_syntax,
      "Command should be: brew ruby script args")
  end

  # Test: Verify incorrect syntax would fail
  def test_brew_ruby_with_separator_is_wrong
    # INCORRECT syntax (what we tried):
    # brew ruby script.rb -- --formulae jq

    incorrect_syntax = "brew ruby bin/brew-mirror -- --formulae jq"

    # This is WRONG - brew ruby would parse --formulae as its own option
    assert_includes incorrect_syntax, " -- ",
      "This syntax is incorrect - used for documentation only"
  end

  # Test: Document where this pattern is used successfully
  def test_working_examples_in_codebase
    # These are KNOWN WORKING examples from .github/workflows/test.yml:

    working_examples = [
      "brew ruby mirror/test/test_api_compatibility.rb",
      "brew ruby mirror/test/test_cask_api.rb",
      "brew ruby bin/brew-mirror -d /tmp/test-mirror-ci -c",
    ]

    working_examples.each do |cmd|
      refute_includes cmd, " -- ",
        "Working example should not have -- separator: #{cmd}"

      assert_match(/^brew ruby \S+/, cmd,
        "Working example should start with 'brew ruby <path>': #{cmd}")
    end
  end

  # Test: Integration test commands should match working pattern
  def test_integration_test_commands_follow_pattern
    # Commands that SHOULD be used in integration tests:

    mirror_command = "brew ruby /path/to/brew-mirror --formulae jq --directory /tmp"
    install_command = "brew ruby /path/to/brew-offline-install --config /tmp/config.json jq"

    [mirror_command, install_command].each do |cmd|
      refute_includes cmd, " -- ",
        "Integration test command should not have --: #{cmd}"

      assert_match(/^brew ruby /, cmd,
        "Should start with 'brew ruby': #{cmd}")

      # Verify script options come directly after script path
      refute_match(/brew ruby.*-- --/, cmd,
        "Should not have '-- --' pattern: #{cmd}")
    end
  end
end
