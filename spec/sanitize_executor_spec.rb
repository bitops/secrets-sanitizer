# Copyright (C) 2016-Present Pivotal Software, Inc. All rights reserved.
#
# This program and the accompanying materials are made available under
# the terms of the under the Apache License, Version 2.0 (the "License”);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.Copyright (C) 2016-Present Pivotal Software, Inc. # All rights reserved.
#
# This program and the accompanying materials are made available under
# the terms of the under the Apache License, Version 2.0 (the "License”);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.#!/bin/sh

require 'spec_helper'

describe Sanitizer::SanitizeExecutor do
  before :each do
    @work_dir = File.dirname(__FILE__)
    @tmp_dir=`mktemp -d`.strip
    `cp -rf #{@work_dir}/fixture/* #{@tmp_dir}/`
  end

  after :each do
   `rm -rf #{@tmp_dir}`
  end

  def check_sanitize_success(file_basename, keys, expect_value)
    manifest_post_sanitize = YAML.load_file("#{@tmp_dir}/#{file_basename}.yml")
    secret_node = manifest_post_sanitize
    keys.each do |key|
      secret_node = secret_node.fetch(key)
    end
    sanitize_key = keys.join('_')
    expect(secret_node).to eq("{{#{sanitize_key}}}")

    expect(File).to exist("#{@tmp_dir}/secrets-#{file_basename}.json")
    secretsFile = File.read("#{@tmp_dir}/secrets-#{file_basename}.json")
    secrets = JSON.parse(secretsFile)
    expect(secrets[sanitize_key]).to eq(expect_value)
    return manifest_post_sanitize
  end


  it 'extracts secrets to another file and replaces with mustache style syntax' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_1.yml",  "#{@tmp_dir}/config_1", "#{@tmp_dir}")
    keys=['bla','foo', 'bar_secret_key']

    manifest_post_sanitize = check_sanitize_success('manifest_1',keys, 'bar_secret_value')

    not_secret_node = manifest_post_sanitize['bla']['foo']['bar_not_secret_key']
    expect(not_secret_node).to eq("bar_not_secret_value")
    special_char_value_node = manifest_post_sanitize['bla']['foo']['special_char_value_key']
    expect(special_char_value_node).to eq("*")
  end

  it 'works with multiple match' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_1.yml",  "#{@tmp_dir}/config_2", "#{@tmp_dir}")
    keys=['bla','foo', 'bar_secret_key']
    check_sanitize_success('manifest_1',keys, 'bar_secret_value')
    keys=['bla','foo', 'bar_secret_key_1']
    manifest_post_sanitize = check_sanitize_success('manifest_1',keys, 'bar_secret_value_1')
    special_char_value_node = manifest_post_sanitize['bla']['foo']['special_char_value_key']
    expect(special_char_value_node).to eq("*")
  end

  it 'works with multiple line value keys' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_3.yml",  "#{@tmp_dir}/config_3", "#{@tmp_dir}")
    expect_value = \
"----------BEGIN RSA PRIVATE KEY--------
ASDASDASDSADSAD
----------END RSA PRIVATE KEY----------
"
    keys=['bla','foo', 'multi_line_value_key']
    check_sanitize_success('manifest_3',keys, expect_value)
  end

  it 'works with multiple line value keys' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_4.yml",  "#{@tmp_dir}/config_4", "#{@tmp_dir}")
    keys=['instance_groups', 0 , 'templates', 0, 'properties', 'tsa', 'private_key']
    check_sanitize_success('manifest_4', keys, 'redacted')
  end

  it 'does not create secret file if no secrets matched the pattern' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_1.yml",  "#{@tmp_dir}/config_4", "#{@tmp_dir}")
    expect(File).to_not exist("#{@tmp_dir}/secrets-manifest_1.json")
  end

  it 'ignores values already in mustache syntax' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_5.yml",  "#{@tmp_dir}/config_1", "#{@tmp_dir}", Logger.new(nil))
    manifest_post_sanitize = YAML.load_file("#{@tmp_dir}/manifest_5.yml")
    mustache_value_key = manifest_post_sanitize['bla']['foo']['bar_secret_key']
    expect(mustache_value_key).to eq("{{bar_secret_value}}")
  end

  it 'ignores null or empty values for matching keys' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_6.yml",  "#{@tmp_dir}/config_1", "#{@tmp_dir}", Logger.new(nil))
    manifest_post_sanitize = YAML.load_file("#{@tmp_dir}/manifest_6.yml")
    mustache_value_key = manifest_post_sanitize['bla']['foo']['bar_secret_key']
    expect(mustache_value_key).to eq("{{bla_foo_bar_secret_key}}")
  end

  it 'ignores values already in spiff syntax' do
    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_7.yml",  "#{@tmp_dir}/config_1", "#{@tmp_dir}", Logger.new(nil))
    manifest_post_sanitize = YAML.load_file("#{@tmp_dir}/manifest_7.yml")
    mustache_value_key = manifest_post_sanitize['bla']['foo']['bar_secret_key']
    expect(mustache_value_key).to eq("((bar_secret_value))")
  end

  it 'appends to the secrets file if one already exists' do
    existing_secrets = JSON.parse('{"hello" : "world"}')
    json_secret_file_path = File.join(
      File.expand_path(@tmp_dir),
      "/secrets-manifest_1.json"
    )
    File.open(json_secret_file_path, 'w') do |file|
      file.write existing_secrets.to_json
    end

    Sanitizer::SanitizeExecutor.execute("#{@tmp_dir}/manifest_1.yml",  "#{@tmp_dir}/config_1", "#{@tmp_dir}")
    keys=['bla','foo', 'bar_secret_key']

    manifest_post_sanitize = check_sanitize_success('manifest_1',keys, 'bar_secret_value')

    secretsFile = File.read(json_secret_file_path)
    secrets = JSON.parse(secretsFile)
    expect(secrets["hello"]).to eq("world")

  end
end
