#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../lib/offlinebrew_config'

# Test OfflinebrewConfig module for home directory detection
# and configuration file management
class OfflinebrewConfigTest < Minitest::Test
  def setup
    @original_env = {}
    ['HOME', 'USER', 'REAL_HOME', 'SUDO_USER'].each do |key|
      @original_env[key] = ENV[key]
    end

    @test_home = Dir.mktmpdir('offlinebrew-config-test')
  end

  def teardown
    # Restore original environment
    @original_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    # Clean up test directory
    FileUtils.rm_rf(@test_home) if @test_home && Dir.exist?(@test_home)
  end

  # ============================================================================
  # Home Directory Detection Tests
  # ============================================================================

  def test_real_home_uses_real_home_env_first
    ENV['REAL_HOME'] = @test_home
    ENV['HOME'] = '/fake/home'

    result = OfflinebrewConfig.real_home_directory

    assert_equal @test_home, result, "Should use REAL_HOME when set"
  end

  def test_real_home_uses_home_env_when_reasonable
    ENV.delete('REAL_HOME')
    ENV['HOME'] = @test_home

    result = OfflinebrewConfig.real_home_directory

    assert_equal @test_home, result, "Should use HOME when reasonable"
  end

  def test_real_home_rejects_var_root
    ENV.delete('REAL_HOME')
    ENV['HOME'] = '/var/root'
    ENV['USER'] = 'testuser'

    result = OfflinebrewConfig.real_home_directory

    refute_equal '/var/root', result, "Should reject /var/root as HOME"
  end

  def test_real_home_constructs_from_user_on_macos
    ENV.delete('REAL_HOME')
    ENV.delete('HOME')
    ENV['USER'] = 'testuser'

    result = OfflinebrewConfig.real_home_directory

    # On macOS (where /Users exists)
    if File.exist?('/Users')
      assert_equal '/Users/testuser', result
    # On Linux (where /home exists)
    elsif File.exist?('/home')
      assert_equal '/home/testuser', result
    else
      # Neither exists, will fall back to current directory
      assert result.is_a?(String)
    end
  end

  # ============================================================================
  # Config Path Tests
  # ============================================================================

  def test_config_dir_returns_offlinebrew_dir
    ENV['REAL_HOME'] = @test_home

    result = OfflinebrewConfig.config_dir

    assert_equal File.join(@test_home, '.offlinebrew'), result
  end

  def test_config_path_returns_config_json
    ENV['REAL_HOME'] = @test_home

    result = OfflinebrewConfig.config_path

    expected = File.join(@test_home, '.offlinebrew', 'config.json')
    assert_equal expected, result
  end

  def test_urlmap_path_returns_urlmap_json
    ENV['REAL_HOME'] = @test_home

    result = OfflinebrewConfig.urlmap_path

    expected = File.join(@test_home, '.offlinebrew', 'urlmap.json')
    assert_equal expected, result
  end

  # ============================================================================
  # Configuration Management Tests
  # ============================================================================

  def test_configured_returns_false_when_no_config
    ENV['REAL_HOME'] = @test_home

    result = OfflinebrewConfig.configured?

    refute result, "Should return false when config doesn't exist"
  end

  def test_configured_returns_true_when_both_files_exist
    ENV['REAL_HOME'] = @test_home
    config_dir = OfflinebrewConfig.config_dir
    FileUtils.mkdir_p(config_dir)

    File.write(OfflinebrewConfig.config_path, '{}')
    File.write(OfflinebrewConfig.urlmap_path, '{}')

    result = OfflinebrewConfig.configured?

    assert result, "Should return true when both files exist"
  end

  def test_ensure_config_dir_creates_directory
    ENV['REAL_HOME'] = @test_home

    result = OfflinebrewConfig.ensure_config_dir

    assert result, "ensure_config_dir should return true"
    assert Dir.exist?(OfflinebrewConfig.config_dir), "Config directory should exist"
  end

  def test_load_config_reads_json_file
    ENV['REAL_HOME'] = @test_home
    OfflinebrewConfig.ensure_config_dir

    config_data = { baseurl: 'http://localhost:9876', commit: 'abc123' }
    File.write(OfflinebrewConfig.config_path, config_data.to_json)

    result = OfflinebrewConfig.load_config

    assert_equal 'http://localhost:9876', result[:baseurl]
    assert_equal 'abc123', result[:commit]
  end

  def test_load_config_raises_when_file_missing
    ENV['REAL_HOME'] = @test_home

    error = assert_raises(RuntimeError) do
      OfflinebrewConfig.load_config
    end

    assert_match /Config file not found/, error.message
  end

  def test_load_urlmap_reads_json_file
    ENV['REAL_HOME'] = @test_home
    OfflinebrewConfig.ensure_config_dir

    urlmap_data = {
      'https://example.com/file.tar.gz' => 'mirror/file.tar.gz'
    }
    File.write(OfflinebrewConfig.urlmap_path, urlmap_data.to_json)

    result = OfflinebrewConfig.load_urlmap

    assert_equal 'mirror/file.tar.gz', result['https://example.com/file.tar.gz']
  end

  def test_load_urlmap_raises_when_file_missing
    ENV['REAL_HOME'] = @test_home

    error = assert_raises(RuntimeError) do
      OfflinebrewConfig.load_urlmap
    end

    assert_match /Urlmap file not found/, error.message
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  def test_full_workflow
    ENV['REAL_HOME'] = @test_home

    # 1. Create config directory
    OfflinebrewConfig.ensure_config_dir
    assert Dir.exist?(OfflinebrewConfig.config_dir)

    # 2. Write config files
    config = { baseurl: 'http://mirror.local', commit: 'def456' }
    urlmap = { 'https://example.com/test.tar.gz' => 'files/test.tar.gz' }

    File.write(OfflinebrewConfig.config_path, config.to_json)
    File.write(OfflinebrewConfig.urlmap_path, urlmap.to_json)

    # 3. Verify configured
    assert OfflinebrewConfig.configured?

    # 4. Load and verify
    loaded_config = OfflinebrewConfig.load_config
    loaded_urlmap = OfflinebrewConfig.load_urlmap

    assert_equal 'http://mirror.local', loaded_config[:baseurl]
    assert_equal 'def456', loaded_config[:commit]
    assert_equal 'files/test.tar.gz', loaded_urlmap['https://example.com/test.tar.gz']
  end

  def test_sudo_user_detection_without_getent
    skip unless RUBY_PLATFORM.include?('darwin')

    ENV.delete('REAL_HOME')
    ENV['SUDO_USER'] = ENV['USER']  # Simulate sudo

    # This should not crash even if getent is not available (macOS)
    result = OfflinebrewConfig.real_home_directory

    assert result.is_a?(String)
    assert !result.empty?
  end
end
