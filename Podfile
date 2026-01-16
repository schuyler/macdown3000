MIN_DEPLOYMENT_TARGET = '11.0'

platform :osx, MIN_DEPLOYMENT_TARGET

source 'https://github.com/MacDownApp/cocoapods-specs.git'  # Patched libraries.
source 'https://cdn.cocoapods.org/'

project 'MacDown 3000.xcodeproj'

inhibit_all_warnings!

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  pod 'hoedown', '~> 3.0.7', :inhibit_warnings => false
  pod 'JJPluralForm', '~> 2.1'
  pod 'MASPreferences', '~> 1.4'
  # Temporarily disabled - will upgrade to 2.8.1 later
  # pod 'Sparkle', '~> 1.18', :inhibit_warnings => false

  pod 'PAPreferences', '~> 0.5'
end

target "MacDownTests" do
  pod 'PAPreferences', '~> 0.5'
end

target "macdown-cmd" do
  pod 'GBCli', '~> 1.1'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Ensure all pods match the project's minimum deployment target
      if config.build_settings['MACOSX_DEPLOYMENT_TARGET'].to_f < MIN_DEPLOYMENT_TARGET.to_f
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = MIN_DEPLOYMENT_TARGET
      end
    end
  end
end
