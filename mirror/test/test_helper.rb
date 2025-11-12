#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "pathname"

# TestHelper: Shared utilities for offlinebrew tests
#
# Provides:
# - Temporary directory management
# - Mock config/urlmap creation
# - Assertion helpers
# - Stub/mock utilities
module TestHelper
  # Create a temporary directory for testing
  #
  # @yield [String] path to temporary directory
  # @return [void]
  #
  # @example
  #   with_temp_dir do |dir|
  #     File.write(File.join(dir, "test.txt"), "content")
  #   end
  def with_temp_dir
    Dir.mktmpdir do |tmpdir|
      yield tmpdir
    end
  end

  # Create a mock config.json file
  #
  # @param dir [String] directory to create config in
  # @param baseurl [String] base URL for mirror
  # @param taps [Hash] tap configuration
  # @return [String] path to config file
  #
  # @example
  #   config_path = create_mock_config(tmpdir, "http://localhost:8000", {
  #     "homebrew/homebrew-core" => { "commit" => "abc123" }
  #   })
  def create_mock_config(dir, baseurl: "http://localhost:8000", taps: nil)
    config = {
      baseurl: baseurl,
    }

    if taps
      config[:taps] = taps
    else
      # Default: just core tap
      config[:taps] = {
        "homebrew/homebrew-core" => {
          "commit" => "abc1234567890",
          "type" => "formula",
        },
      }
    end

    config_path = File.join(dir, "config.json")
    File.write(config_path, JSON.pretty_generate(config))
    config_path
  end

  # Create a mock urlmap.json file
  #
  # @param dir [String] directory to create urlmap in
  # @param mappings [Hash] URL to filename mappings
  # @return [String] path to urlmap file
  #
  # @example
  #   urlmap_path = create_mock_urlmap(tmpdir, {
  #     "https://example.com/file.dmg" => "abc123.dmg"
  #   })
  def create_mock_urlmap(dir, mappings = {})
    urlmap_path = File.join(dir, "urlmap.json")
    File.write(urlmap_path, JSON.pretty_generate(mappings))
    urlmap_path
  end

  # Create a mock file with specific content
  #
  # @param path [String] path to file
  # @param content [String] file content
  # @param size [Integer, nil] if provided, creates file of specific size
  # @return [String] path to created file
  #
  # @example
  #   create_mock_file("/tmp/test.dmg", "x" * 1000)
  def create_mock_file(path, content = nil, size: nil)
    if size
      # Create file of specific size
      File.open(path, "wb") do |f|
        f.write("x" * size)
      end
    elsif content
      File.write(path, content)
    else
      FileUtils.touch(path)
    end
    path
  end

  # Run a command and capture output
  #
  # @param command [String] command to run
  # @param env [Hash] environment variables
  # @return [Hash] { stdout:, stderr:, status: }
  #
  # @example
  #   result = run_command("echo hello", env: {"FOO" => "bar"})
  #   assert_equal "hello\n", result[:stdout]
  def run_command(command, env: {})
    require "open3"

    stdout, stderr, status = Open3.capture3(env, command)

    {
      stdout: stdout,
      stderr: stderr,
      status: status,
      exitstatus: status.exitstatus,
      success: status.success?,
    }
  end

  # Stub a constant for the duration of a block
  #
  # @param mod [Module] module or class containing constant
  # @param const [Symbol] constant name
  # @param value [Object] value to stub with
  # @yield block to run with stubbed constant
  # @return [void]
  #
  # @example
  #   stub_const(Object, :BREW_OFFLINE_CONFIG, "/tmp/config.json") do
  #     # BREW_OFFLINE_CONFIG is now "/tmp/config.json"
  #   end
  def stub_const(mod, const, value)
    original = mod.const_get(const) if mod.const_defined?(const)
    original_defined = mod.const_defined?(const)

    mod.const_set(const, value)
    yield
  ensure
    if original_defined
      mod.const_set(const, original)
    else
      mod.send(:remove_const, const)
    end
  end

  # Assert that a command succeeds
  #
  # @param result [Hash] result from run_command
  # @param message [String] failure message
  # @return [void]
  def assert_command_success(result, message = nil)
    msg = message || "Command failed: #{result[:stderr]}"
    assert result[:success], msg
  end

  # Assert that a command fails
  #
  # @param result [Hash] result from run_command
  # @param message [String] failure message
  # @return [void]
  def assert_command_failure(result, message = nil)
    msg = message || "Command succeeded but should have failed"
    refute result[:success], msg
  end

  # Assert that output contains a string
  #
  # @param output [String] output to search
  # @param expected [String] string to find
  # @param message [String] failure message
  # @return [void]
  def assert_output_contains(output, expected, message = nil)
    msg = message || "Expected output to contain '#{expected}'\nGot: #{output}"
    assert output.include?(expected), msg
  end

  # Assert that output does not contain a string
  #
  # @param output [String] output to search
  # @param unexpected [String] string that should not be present
  # @param message [String] failure message
  # @return [void]
  def assert_output_not_contains(output, unexpected, message = nil)
    msg = message || "Expected output to NOT contain '#{unexpected}'\nGot: #{output}"
    refute output.include?(unexpected), msg
  end

  # Assert that a file exists
  #
  # @param path [String] file path
  # @param message [String] failure message
  # @return [void]
  def assert_file_exists(path, message = nil)
    msg = message || "Expected file to exist: #{path}"
    assert File.exist?(path), msg
  end

  # Assert that a file does not exist
  #
  # @param path [String] file path
  # @param message [String] failure message
  # @return [void]
  def refute_file_exists(path, message = nil)
    msg = message || "Expected file to NOT exist: #{path}"
    refute File.exist?(path), msg
  end

  # Assert JSON file contains expected data
  #
  # @param path [String] path to JSON file
  # @param expected [Hash] expected data (subset match)
  # @param message [String] failure message
  # @return [void]
  def assert_json_file(path, expected, message = nil)
    assert_file_exists(path)

    json = JSON.parse(File.read(path), symbolize_names: true)

    expected.each do |key, value|
      msg = message || "Expected JSON[#{key}] = #{value.inspect}, got #{json[key].inspect}"
      assert_equal value, json[key], msg
    end
  end
end

# Include TestHelper in all test cases
class Minitest::Test
  include TestHelper
end
