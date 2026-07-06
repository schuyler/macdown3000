Pod::Spec.new do |s|
  s.name         = 'cmark-gfm'
  s.version      = '0.29.0.gfm.13'
  s.summary      = "GitHub's cmark-gfm Markdown parser, vendored for " \
                   'MacDown with the mdmark renderer glue.'
  s.description  = <<-DESC
    Vendored copy of github/cmark-gfm 0.29.0.gfm.13 (CommonMark + GFM
    extensions) plus MacDown's mdmark renderer layer, which reproduces the
    HTML contract previously provided by hoedown + hoedown_html_patch.c:
    heading id slugs, Prism-compatible code blocks, interactive task lists,
    and the <ul class="toc"> table of contents. See README-MACDOWN.md for
    the list of local modifications to upstream sources.
  DESC
  s.homepage     = 'https://github.com/github/cmark-gfm'
  s.license      = { :type => 'BSD-2-Clause', :file => 'COPYING' }
  s.authors      = { 'John MacFarlane' => 'jgm@berkeley.edu',
                     'GitHub' => 'https://github.com' }
  s.source       = { :git => 'https://github.com/github/cmark-gfm.git',
                     :tag => '0.29.0.gfm.13' }

  s.platform     = :osx, '11.0'
  s.requires_arc = false

  s.source_files        = 'src/*.{c,h}'
  s.preserve_paths      = 'src/*.inc', 'README-MACDOWN.md'
  s.public_header_files = 'src/cmark-gfm.h',
                          'src/cmark-gfm-extension_api.h',
                          'src/cmark-gfm-core-extensions.h',
                          'src/cmark-gfm_export.h',
                          'src/cmark-gfm_version.h',
                          'src/config.h',
                          'src/mdmark.h'
  s.header_dir          = 'cmark-gfm'

  s.compiler_flags = '-DCMARK_GFM_STATIC_DEFINE',
                     '-DCMARK_GFM_EXTENSIONS_STATIC_DEFINE'
end
