# MacDown 3000 Website

This directory contains the MacDown 3000 website, hosted at https://schuyler.github.io/macdown3000

## Local Development

### Prerequisites
- Ruby 2.5 or higher
- Bundler

### Setup
```bash
# Install dependencies
bundle install

# Run local server
bundle exec jekyll serve

# View the site at http://localhost:4000/macdown3000
```

## Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the main branch.

### GitHub Pages Configuration
1. Go to repository Settings → Pages
2. Set Source to: Deploy from a branch
3. Set Branch to: `main` or your preferred branch
4. Set Folder to: `/docs`
5. Save

The site will be available at https://schuyler.github.io/macdown3000

## Structure

```
docs/
├── _config.yml          # Jekyll configuration
├── _layouts/            # Page layouts
│   └── default.html     # Main layout template
├── assets/              # Static assets
│   ├── css/
│   │   └── style.css    # Main stylesheet
│   └── images/          # Images and graphics
├── index.html           # Homepage
└── README.md           # This file
```

## Content

The website is adapted from the original MacDown homepage (https://macdown.uranusjr.com) with updates for MacDown 3000:
- Emphasis on "MacDown Continued" concept
- Focus on Apple Silicon support and modern macOS
- Attribution to original Mou and MacDown creators
- Updated download information and GitHub links
- Modern Markdown standards focus

## License

The website content is released under the MIT License, consistent with the MacDown 3000 project.
