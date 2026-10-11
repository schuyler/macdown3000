require 'yaml'
require 'tmpdir'
require 'open3'
require 'json'

ROOT = File.expand_path('../..', __dir__)
Dir.chdir(ROOT)

def steps(path)
  config = YAML.load_file(path)
  config['runs'] ? config['runs']['steps'] : config['jobs'].values.flat_map { |job| job['steps'] || [] }
end

def assert(condition, message)
  raise message unless condition
end

paths = Dir['.github/{actions/*,workflows}/*.yml']
blocks = 0
paths.each do |path|
  steps(path).each do |step|
    next unless step['run']
    script = step['run'].gsub(/\$\{\{.*?\}\}/, 'audit-placeholder')
    _, error, status = Open3.capture3('bash', '-n', stdin_data: script)
    assert(status.success?, "#{path}: #{step['name']}: #{error}")
    blocks += 1
  end
end

Dir.mktmpdir('macdown-workflow-contracts') do |directory|
  version_script = steps('.github/workflows/release.yml').find { |s| s['name'] == 'Extract version from tag or input' }.fetch('run')
  environment = { 'GITHUB_REF' => 'refs/heads/main', 'GITHUB_ENV' => File.join(directory, 'env') }
  environment['PROVIDED_VERSION'] = '3000.1.0-beta.2'
  _, _, status = Open3.capture3(environment, 'bash', '-e', stdin_data: version_script)
  assert(status.success?, 'Valid version was rejected')
  assert(File.read(environment['GITHUB_ENV']).include?('VERSION=3000.1.0-beta.2'), 'Valid version was not exported')
  marker = File.join(directory, 'injection')
  environment['PROVIDED_VERSION'] = "\"; touch #{marker}; #"
  _, _, status = Open3.capture3(environment, 'bash', '-e', stdin_data: version_script)
  assert(!status.success? && !File.exist?(marker), 'Invalid input executed or was accepted')

  output = File.join(directory, 'argv.json')
  mock = File.join(directory, 'xcodebuild')
  File.write(mock, "#!/usr/bin/env ruby\nrequire 'json'\nFile.write(ENV.fetch('AUDIT_ARGV_OUTPUT'), JSON.dump(ARGV))\n")
  File.chmod(0755, mock)
  build_script = steps('.github/actions/build-macdown/action.yml').first.fetch('run')
  env = { 'PATH' => "#{directory}:#{ENV['PATH']}", 'AUDIT_ARGV_OUTPUT' => output,
          'SIGNING_ENABLED' => 'false', 'MARKETING_VERSION_INPUT' => '1.0.0 with spaces',
          'BUILD_NUMBER_INPUT' => '42', 'TEAM_ID_INPUT' => '' }
  _, error, status = Open3.capture3(env, 'bash', '-e', stdin_data: build_script, chdir: directory)
  assert(status.success?, error)
  arguments = JSON.parse(File.read(output))
  assert(arguments.include?('MARKETING_VERSION=1.0.0 with spaces'), 'Build settings were split into arguments')
  assert(arguments.include?('CURRENT_PROJECT_VERSION=42'), 'Build number lost')

  generator = File.join(ROOT, 'Dependency/peg-markdown-highlight/greg/greg')
  grammar = File.join(directory, 'long.leg')
  rule = 'r' * 2048
  File.write(grammar, "start = #{rule}\n#{rule} = 'a' { $$ = 1; }\n")
  parser, error, status = Open3.capture3(generator, grammar)
  assert(status.success? && parser.include?("_1_#{rule}"), "Long grammar identifier failed: #{error}")
end

_, error, status = Open3.capture3({ 'GITHUB_ACTIONS' => nil }, 'bash', 'Tools/smoke_launch.sh')
assert(!status.success? && error.include?('isolated GitHub Actions runner'), 'Smoke helper permits local preference reset')
puts "#{paths.length} YAML files, #{blocks} shell syntax blocks; version, structured arguments, generator and CI guard contracts passed"
