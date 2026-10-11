require 'yaml'
require 'tmpdir'
require 'open3'
require 'json'

root = File.expand_path('../..', __dir__)
steps = YAML.load_file(File.join(root, '.github/workflows/update-website.yml'))
            .fetch('jobs').fetch('update-website').fetch('steps')
script = steps.find { |step| step['name'] == 'Get latest release info' }.fetch('run')
script = script.gsub('${{ github.repository }}', 'test/macdown')

Dir.mktmpdir('macdown-website-contracts') do |directory|
  Dir.mkdir(File.join(directory, 'bin'))
  Dir.mkdir(File.join(directory, 'docs'))
  Dir.mkdir(File.join(directory, 'docs/_data'))
  marker = File.join(directory, 'injection')
  stable_tag = "v1.2.3'; touch #{marker}; #"
  fixture = {
    tagName: stable_tag, publishedAt: '2026-10-01T00:00:00Z', url: 'https://example.invalid/release',
    isPrerelease: false, assets: [{ name: 'MacDown.dmg', size: 1048576 }]
  }
  File.write(File.join(directory, 'release.json'), JSON.dump(fixture))
  File.write(File.join(directory, 'pages.json'), JSON.dump([
    [{ draft: false, prerelease: false, published_at: '2026-10-06T00:00:00Z', tag_name: 'v2.0.0' }],
    [{ draft: false, prerelease: true, published_at: '2026-10-04T00:00:00Z', tag_name: 'v3.0.0-beta.1' },
     { draft: true, prerelease: true, published_at: '2026-10-05T00:00:00Z', tag_name: 'v4.0.0-beta.1' }]
  ]))
  gh = File.join(directory, 'bin/gh')
  File.write(gh, <<~'SH')
    #!/bin/bash
    if [[ "$1" == api ]]; then
      while [[ "$1" != --jq ]]; do shift; done
      jq -r "$2" pages.json
    elif [[ "$2" == list ]]; then
      jq -r .tagName release.json
    elif [[ "$2" == view ]]; then
      if [[ "$3" == v3.0.0-beta.1 ]]; then
        jq '.tagName = "v3.0.0-beta.1" | .isPrerelease = true' release.json
      else
        cat release.json
      fi
    else
      exit 42
    fi
  SH
  File.chmod(0755, gh)
  env = { 'PATH' => "#{directory}/bin:#{ENV['PATH']}",
          'GITHUB_ENV' => File.join(directory, 'env'), 'GITHUB_REPOSITORY' => 'test/macdown' }
  _, error, status = Open3.capture3(env, 'bash', '-e', '-o', 'pipefail', stdin_data: script, chdir: directory)
  raise error unless status.success?
  raise 'Metadata executed shell code' if File.exist?(marker)
  result = JSON.parse(File.read(File.join(directory, 'docs/_data/latest.json')))
  raise 'Stable metadata was corrupted' unless result['stable']['tagName'] == stable_tag
  raise 'Older prerelease on later page was lost' unless result['prerelease']['tagName'] == 'v3.0.0-beta.1'
  puts 'Website metadata remains literal; latest published prerelease survives pagination and newer stable/draft releases'
end
