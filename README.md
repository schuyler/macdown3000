# MacDown 3000

[![Tests](https://github.com/schuyler/macdown3000/workflows/Tests/badge.svg)](https://github.com/schuyler/macdown3000/actions)

MacDown 3000 is a free Markdown editor for macOS, available under the MIT License. It continues the legacy started by Chen Luo's [Mou](http://25.io/mou/) and carried forward by Tzu-ping Chung's [MacDown](https://macdown.uranusjr.com).

Visit the [project website](https://schuyler.github.io/macdown3000/) for more information, or download from the [releases](https://github.com/schuyler/macdown3000/releases) page.

## About MacDown 3000

In 2025, there's still a need for a modern, lightweight Markdown editor for macOS with live preview capabilities. MacDown 3000 is essentially *MacDown Continued*. The focus is on keeping MacDown up to date with modern Markdown best practices and maintaining compatibility with current library dependencies.

MacDown 3000 supports macOS 11.0 (Big Sur) and later, exclusively on Apple Silicon.

This project honors the original intentions and contributions of both Mou and MacDown while ensuring that this valuable tool remains available and actively maintained for today's Mac users.

## Download & Install

**Version 3000.0.0** - Coming Soon

Download the latest release from the [GitHub Releases](https://github.com/schuyler/macdown3000/releases) page, unzip, and drag the app to your Applications folder.

### System Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon (M-series processor)
- Intel Macs are not supported

### Important Note

MacDown 3000 is not signed with a paid Apple developer certificate. macOS will display an "unidentified developer" warning. To open the app:

1. Go to System Settings → Privacy & Security
2. Find the blocked app message and click "Open Anyway"
3. Alternatively, right-click the app and choose "Open" the first time you launch it

## Screenshot

![screenshot](assets/screenshot.png)

## Features

### Live Preview & Markdown Rendering

MacDown 3000 uses Hoedown to convert Markdown to HTML with live preview as you type. It supports:

- **Fenced code blocks** with language identifiers
- **GitHub Flavored Markdown** including tables, strikethrough, and autolinks
- **Task lists** for GFM-style checkboxes
- **Customizable rendering options** in Preferences

### Syntax Highlighting

Code blocks get syntax highlighting via Prism, supporting numerous programming and markup languages.

### Additional Rendering Tools

- **Math notation** using TeX-like syntax ($$...$$, \[...\], \(...\), and optional $...$ blocks)
- **Jekyll front-matter** for static site generators
- **Export to HTML or PDF** with customizable styling

### Editor Features

- **Auto-completion**: Automatic bracket and quote pairing, list continuation, and formatting shortcuts (customizable or disable)
- **Apple Silicon optimized**: Built natively for M-series Macs
- **Modern Markdown**: Supports CommonMark and GitHub Flavored Markdown

## Development

### Requirements

If you wish to build MacDown 3000 yourself, you will need the following components/tools:

* macOS SDK (11.0 or later)
* Git
* [Bundler](http://bundler.io)

> Note: Old versions of CocoaPods are not supported. Please use Bundler to execute CocoaPods, or make sure your CocoaPods is later than shown in `Gemfile.lock`.

> Note: The Command Line Tools (CLT) should be unnecessary. If you failed to compile without it, please install CLT with
>
>     xcode-select --install
>
> and report back.

An appropriate SDK should be bundled with recent versions of Xcode.

### Environment Setup

After cloning the repository, run the following commands inside the repository root (directory containing this `README.md` file):

    git submodule update --init
    bundle install
    bundle exec pod install
    make -C Dependency/peg-markdown-highlight

and open `MacDown.xcworkspace` in Xcode. The first command initialises the dependency submodule(s) used in MacDown; the second one installs dependencies managed by CocoaPods.

Refer to the official guides of Git and CocoaPods if you need more instructions. If you run into build issues later on, try running the following commands to update dependencies:

    git submodule update
    bundle exec pod install

## License

MacDown 3000 is released under the terms of MIT License. You may find the content of the license [here](http://opensource.org/licenses/MIT), or inside the `LICENSE` directory.

You may find full text of licenses about third-party components in the `LICENSE` directory, or the **About MacDown** panel in the application.

The following editor themes and CSS files are extracted from [Mou](http://mouapp.com), courtesy of Chen Luo:

* Mou Fresh Air
* Mou Fresh Air+
* Mou Night
* Mou Night+
* Mou Paper
* Mou Paper+
* Tomorrow
* Tomorrow Blue
* Tomorrow+
* Writer
* Writer+
* Clearness
* Clearness Dark
* GitHub
* GitHub2

## Contributing & Support

MacDown 3000 is Free Software under the MIT License. Contributions are welcome!

Please [file an issue](https://github.com/schuyler/macdown3000/issues/new) on GitHub for bug reports, feature requests, or questions. **Please search first to make sure no-one has reported the same issue already** before opening one yourself.

MacDown 3000 depends on other open source projects, such as [Hoedown](https://github.com/hoedown/hoedown) for Markdown-to-HTML rendering, [Prism](http://prismjs.com) for syntax highlighting (in code blocks), and [PEG Markdown Highlight](https://github.com/ali-rantakari/peg-markdown-highlight) for editor highlighting. If you find problems when using those particular features, you can also consider reporting them directly to upstream projects as well as to MacDown 3000's issue tracker.

## Support MacDown 3000

Donations help cover the cost of the Apple developer license ($99/year). Any proceeds beyond our maintenance costs will be donated to the [Signal Foundation](https://signal.org/donate/).

[Donate via PayPal](https://www.paypal.com/donate/?business=22WG7CGNSSF8C&no_recurring=0&amount=5&item_name=Thank+you+for+supporting+MacDown+3000.+Once+our+maintenance+costs+are+covered%2C+further+donations+will+go+the+Signal+Foundation.&currency_code=USD)
