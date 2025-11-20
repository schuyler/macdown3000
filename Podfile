platform :osx, "10.8"

source 'https://github.com/MacDownApp/cocoapods-specs.git'  # Patched libraries.
source 'https://cdn.cocoapods.org/'

project 'MacDown.xcodeproj'

inhibit_all_warnings!

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  pod 'hoedown', '~> 3.0.7', :inhibit_warnings => false
  pod 'JJPluralForm', '~> 2.1'
  pod 'LibYAML', '~> 0.1'
  pod 'M13OrderedDictionary', '~> 1.1'
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
