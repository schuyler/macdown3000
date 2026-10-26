#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Add one release to the Sparkle appcast at
docs/sparkle/macdown3000/stable/appcast.xml.

Renders a single <item>, signs the DMG with Sparkle's sign_update, splices the
item into the feed, and validates the result. See
plans/sparkle-appcast-automation.md for the design and
plans/release-checklist.md for the procedure that invokes it.

The signing key is read from standard input and is passed to sign_update the
same way. It is never placed in argv, in the environment, or in a file.

Existing feed content is never rewritten. The script inserts text and parses
the result once; that single parse is the whole validation story. Preserve
this -- re-serializing the feed would destroy CDATA sections, comments and
processing instructions in items already published.
"""

import argparse
import base64
import os
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.sax import saxutils


SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'

DEFAULT_SIGN_UPDATE = './Pods/Sparkle/bin/sign_update'

DEFAULT_APPCAST = 'docs/sparkle/macdown3000/stable/appcast.xml'

DEFAULT_GIT = 'git'

DEFAULT_STAPLER = 'xcrun stapler'

DEFAULT_PBXPROJ = 'MacDown 3000.xcodeproj/project.pbxproj'

DEFAULT_RELEASE_URL_BASE = (
    'https://github.com/schuyler/macdown3000/releases/download')

BUNDLE_VERSION_RE = re.compile(r'\A[A-Za-z0-9._-]+\Z')

SIGNATURE_RE = re.compile(r'\A[A-Za-z0-9+/]+={0,2}\Z')

RELEASE_VERSION_RE = re.compile(r'\A\d+(?:\.\d+)+(-(?:rc|beta)\.\d+)?\Z')

DEPLOYMENT_TARGET_RE = re.compile(r'MACOSX_DEPLOYMENT_TARGET\s*=\s*([\d.]+)')

ED25519_SIGNATURE_BYTES = 64

CHANNELS = ('', 'beta')

# Flags --release owns; a partial override alongside it is the transcription
# hazard release mode exists to remove (3.2).
RELEASE_CONFLICT_FLAGS = (
    ('--dmg', 'dmg'),
    ('--url', 'url'),
    ('--description-file', 'description_file'),
    ('--bundle-version', 'bundle_version'),
    ('--short-version', 'short_version'),
    ('--minimum-system-version', 'minimum_system_version'),
    ('--channel', 'channel'),
)

# The same flags, required in explicit mode -- optional (default None) at
# the argparse level so --release can detect whether they were passed.
REQUIRED_EXPLICIT_FLAGS = (
    ('--dmg', 'dmg'),
    ('--url', 'url'),
    ('--description-file', 'description_file'),
    ('--bundle-version', 'bundle_version'),
    ('--short-version', 'short_version'),
    ('--minimum-system-version', 'minimum_system_version'),
)

ITEM_ANCHOR = '    <item>'
CHANNEL_ANCHOR = '  </channel>'

DOCUMENT_HEAD = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<rss version="2.0" xmlns:sparkle="%s">\n'
    '  <channel>\n'
    '    <title>MacDown 3000</title>\n'
    '    <link>https://macdown.app/</link>\n'
    '    <description>Updates for MacDown 3000, a Markdown editor for '
    'macOS.</description>\n'
    '    <language>en</language>\n'
    '    <!-- items here, newest first -->\n'
) % SPARKLE_NS

DOCUMENT_TAIL = '  </channel>\n</rss>\n'


class Failure(Exception):
    """An error to report on stderr before exiting 1."""


class Parser(argparse.ArgumentParser):
    """Reports usage errors the same way as every other failure: exit 1."""

    def error(self, message):
        raise Failure(message)


def attribute(value):
    """A double-quoted attribute value.

    Not saxutils.quoteattr: that switches to single-quote delimiters when the
    value contains a double quote, which would break the fixed layout.
    Escaping the quote before calling it does not help either, because it
    escapes the ampersand of the entity in turn.
    """
    return '"' + saxutils.escape(value, {'"': '&quot;'}) + '"'


def render_item(pub_date, bundle_version, short_version, channel,
                minimum_system_version, description, url, length, signature):
    """One appcast item. Two-space indent, LF, UTF-8.

    The description goes into CDATA verbatim, so nothing in it needs escaping.
    No <guid> (Sparkle does not read one), no <link> (that is infoURL in
    Sparkle 2, which routes the item down the informational-update path), and
    no sparkle:installationType (inferred from the .dmg extension).
    """
    channel_line = ''
    if channel:
        channel_line = ('      <sparkle:channel>%s</sparkle:channel>\n'
                        % saxutils.escape(channel))
    return (
        '    <item>\n'
        '      <title>MacDown 3000 %s</title>\n'
        '      <pubDate>%s</pubDate>\n'
        '      <sparkle:version>%s</sparkle:version>\n'
        '      <sparkle:shortVersionString>%s'
        '</sparkle:shortVersionString>\n'
        '%s'
        '      <sparkle:minimumSystemVersion>%s'
        '</sparkle:minimumSystemVersion>\n'
        '      <description sparkle:format="markdown"><![CDATA[\n'
        '%s\n'
        ']]></description>\n'
        '      <enclosure url=%s length=%s '
        'type="application/octet-stream" sparkle:edSignature=%s/>\n'
        '    </item>\n'
    ) % (
        saxutils.escape(short_version),
        saxutils.escape(pub_date),
        saxutils.escape(bundle_version),
        saxutils.escape(short_version),
        channel_line,
        saxutils.escape(minimum_system_version),
        description,
        attribute(url),
        attribute(str(length)),
        attribute(signature),
    )


def check_no_cdata_terminator(text):
    """`]]>` cannot appear inside a CDATA section (3.4); reject it here with
    a message naming the offending line rather than an opaque parse error
    from the validating parse downstream."""
    for line in text.splitlines():
        if ']]>' in line:
            raise Failure(
                'the description contains "]]>", which cannot appear inside '
                'a CDATA section, on this line:\n  %s\nReword it and re-run.'
                % line)


def read_description(path):
    """The changelog section for this release, normalized to LF and stripped
    to exactly the text that goes between the CDATA brackets."""
    try:
        # newline='' so the normalization below is what does the work, rather
        # than universal-newline translation doing it invisibly.
        with open(path, encoding='utf-8', newline='') as handle:
            text = handle.read()
    except OSError as error:
        raise Failure('cannot read --description-file %s: %s' % (path, error))
    except UnicodeDecodeError as error:
        raise Failure('--description-file %s is not UTF-8: %s'
                      % (path, error))

    text = text.replace('\r\n', '\n').replace('\r', '\n')
    check_no_cdata_terminator(text)

    text = text.strip()
    if not text:
        raise Failure('--description-file %s is empty' % path)
    return text


def find_anchor(text, anchor):
    """Character offset of the start of the first line equal to `anchor`, or
    -1 if there is none.

    splitlines(keepends=True) rejoins to the original exactly, so the running
    offset is exact whatever the file contains.
    """
    offset = 0
    for line in text.splitlines(keepends=True):
        if line.rstrip('\r\n') == anchor:
            return offset
        offset += len(line)
    return -1


def splice(existing, item):
    """`existing` with `item` inserted before the first item, or before the
    end of the channel if there are none. Existing bytes are not touched."""
    offset = find_anchor(existing, ITEM_ANCHOR)
    if offset < 0:
        offset = find_anchor(existing, CHANNEL_ANCHOR)
    if offset < 0:
        raise Failure(
            'found neither a "%s" line nor a "%s" line to splice before. '
            'Is this an appcast?' % (ITEM_ANCHOR, CHANNEL_ANCHOR))
    return existing[:offset] + item + existing[offset:]


def validate(document, bundle_version, appcast, existed):
    """The single validating parse.

    A malformed existing file, a control character in the description, a
    corrupt splice, a re-publish of a version already in the feed and a
    pre-existing duplicate all fail here, before anything is written.
    """
    context = ''
    if existed:
        context = (' The existing file may already have been malformed; '
                   'this script cannot tell the two apart.')
    try:
        root = ET.fromstring(document.encode('utf-8'))
    except ET.ParseError as error:
        raise Failure('the result does not parse as XML: %s.%s Nothing was '
                      'written.' % (error, context))

    matches = [
        item for item in root.findall('./channel/item')
        if (item.findtext('{%s}version' % SPARKLE_NS) or '') == bundle_version
    ]
    if len(matches) != 1:
        raise Failure(
            'expected exactly one item for version %s in the result, found '
            '%d. Nothing was written. If an item for this version is already '
            'in the feed and is wrong, delete its <item> block from %s and '
            're-run.%s'
            % (bundle_version, len(matches), appcast, context))


def sign(sign_update, dmg, key):
    """The base64 EdDSA signature of `dmg`, from Sparkle's sign_update.

    Two things make this call dangerous enough to be worth the checks around
    it. Handed an XML file rather than a DMG, sign_update embeds the signature
    inside that file, rewriting it in place and exiting 0 while printing
    nothing -- so --dmg is validated before we get here. And exit 0 is not by
    itself evidence that a signature was produced, so the output is checked
    too.
    """
    try:
        completed = subprocess.run(
            [sign_update, '-p', '--ed-key-file', '-', dmg],
            input=key, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise Failure('cannot run %s: %s' % (sign_update, error))

    if completed.returncode != 0:
        raise Failure(
            '%s failed with status %d: %s'
            % (sign_update, completed.returncode,
               completed.stderr.decode('utf-8', 'replace').strip()))

    signature = completed.stdout.decode('utf-8', 'replace').strip()
    if not signature or not SIGNATURE_RE.match(signature):
        raise Failure(
            '%s exited 0 but did not print a signature. Got: %r'
            % (sign_update, signature))
    try:
        decoded = base64.b64decode(signature, validate=True)
    except ValueError:  # binascii.Error subclasses it
        raise Failure('%s printed something that is not base64: %r'
                      % (sign_update, signature))
    if len(decoded) != ED25519_SIGNATURE_BYTES:
        raise Failure(
            '%s printed %d bytes of base64, not the %d an Ed25519 signature '
            'is: %r'
            % (sign_update, len(decoded), ED25519_SIGNATURE_BYTES, signature))
    return signature


def write_atomically(path, document):
    """Write via a temp file beside the target and os.replace(), so the live
    feed is never half-written and an error leaves it byte-identical."""
    directory = os.path.dirname(path) or '.'
    try:
        os.makedirs(directory, exist_ok=True)
    except OSError as error:
        raise Failure('cannot create %s: %s' % (directory, error))

    handle = None
    temporary = None
    try:
        descriptor, temporary = tempfile.mkstemp(
            dir=directory, prefix='.appcast-', suffix='.tmp')
        handle = os.fdopen(descriptor, 'w', encoding='utf-8', newline='')
        handle.write(document)
        handle.close()
        handle = None
        # mkstemp creates 0600, and os.replace would carry that onto a feed
        # that is world-readable today.
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
        temporary = None
    except OSError as error:
        raise Failure('cannot write %s: %s' % (path, error))
    finally:
        if handle is not None:
            handle.close()
        if temporary is not None and os.path.exists(temporary):
            os.unlink(temporary)


def check_arguments(args):
    if args.channel not in CHANNELS:
        raise Failure('--channel must be "" or "beta", not %r' % args.channel)

    if not BUNDLE_VERSION_RE.match(args.bundle_version):
        raise Failure('--bundle-version %r must match [A-Za-z0-9._-]+'
                      % args.bundle_version)

    # Reachable from the documented procedure: these are captured from
    # PlistBuddy, which yields an empty string when the key is missing.
    for flag, value in (('--short-version', args.short_version),
                        ('--minimum-system-version',
                         args.minimum_system_version)):
        if not value.strip():
            raise Failure('%s is empty' % flag)

    if not args.url.startswith('https://'):
        raise Failure('--url must be an https:// URL, not %r' % args.url)

    # A stray space survives into the attribute, and XML attribute-value
    # normalization hides it from the operator reading the --dry-run output.
    # Every client then 404s on the download.
    if any(character.isspace() for character in args.url):
        raise Failure('--url contains whitespace: %r' % args.url)

    if not args.dmg.endswith('.dmg'):
        raise Failure('--dmg %s does not end in .dmg' % args.dmg)

    if not os.path.isfile(args.dmg):
        raise Failure('--dmg %s does not exist' % args.dmg)

    if not os.access(args.dmg, os.R_OK):
        raise Failure('--dmg %s is not readable' % args.dmg)

    # samefile rather than realpath: hard links share an inode without
    # sharing a resolved path, and it is the inode sign_update would eat.
    if os.path.exists(args.appcast) and os.path.samefile(args.dmg,
                                                        args.appcast):
        raise Failure(
            '--dmg %s is the appcast %s. sign_update would embed a signature '
            'into the feed and rewrite it in place.'
            % (args.dmg, args.appcast))

    check_sign_update(args.sign_update)


def check_sign_update(path):
    if not os.path.isfile(path):
        raise Failure('sign_update not found at %s (pass --sign-update, or '
                      'run bundle exec pod install)' % path)

    if not os.access(path, os.X_OK):
        raise Failure('sign_update at %s is not executable' % path)


def check_release_conflicts(args):
    """--release owns every per-release input (3.2); a flag from explicit
    mode alongside it is refused by name."""
    for flag, attr in RELEASE_CONFLICT_FLAGS:
        if getattr(args, attr) is not None:
            raise Failure('--release cannot be combined with %s' % flag)


def check_required_explicit_arguments(args):
    missing = [flag for flag, attr in REQUIRED_EXPLICIT_FLAGS
              if getattr(args, attr) is None]
    if missing:
        raise Failure(
            'the following arguments are required: %s' % ', '.join(missing))


def release_version_and_channel(version):
    """(short_version, channel) from an operator-supplied --release VERSION,
    accepted with or without a leading 'v' (3.6 step 1-2). Fails closed: an
    unrecognized shape is an error, never a silent stable classification."""
    short_version = version[1:] if version.startswith('v') else version
    match = RELEASE_VERSION_RE.fullmatch(short_version)
    if not match:
        raise Failure(
            '--release %r does not look like a released version -- expected '
            'e.g. 3000.1.0 or 3000.1.0-rc.1' % version)
    channel = 'beta' if match.group(1) else ''
    return short_version, channel


def run_git(git, subcommand_args):
    # DEVNULL keeps the signing key on stdin from reaching the child.
    try:
        return subprocess.run(
            [git] + subcommand_args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as error:
        raise Failure('cannot run %s: %s' % (git, error))


def resolve_tag(git, tag):
    completed = run_git(git, ['rev-parse', tag])
    if completed.returncode != 0:
        raise Failure(
            'tag %s not found locally. Run git fetch --tags and try again.'
            % tag)


def bundle_version_for_tag(git, tag):
    completed = run_git(git, ['rev-list', '--count', tag])
    if completed.returncode != 0:
        raise Failure(
            'git rev-list --count %s failed: %s'
            % (tag, completed.stderr.decode('utf-8', 'replace').strip()))
    value = completed.stdout.decode('utf-8', 'replace').strip()
    if not value.isdigit():
        raise Failure(
            'git rev-list --count %s did not print a number: %r'
            % (tag, value))
    return value


def minimum_system_version_from_pbxproj(path):
    try:
        with open(path, encoding='utf-8') as handle:
            text = handle.read()
    except OSError as error:
        raise Failure('cannot read --pbxproj %s: %s' % (path, error))

    values = sorted(set(DEPLOYMENT_TARGET_RE.findall(text)))
    if not values:
        raise Failure(
            'no MACOSX_DEPLOYMENT_TARGET found in --pbxproj %s' % path)
    if len(values) > 1:
        raise Failure(
            'MACOSX_DEPLOYMENT_TARGET disagrees across --pbxproj %s: %s'
            % (path, ', '.join(values)))
    return values[0]


def changelog_for_tag(git, tag):
    completed = run_git(git, ['show', '%s:CHANGELOG.md' % tag])
    if completed.returncode != 0:
        raise Failure(
            'git show %s:CHANGELOG.md failed: %s'
            % (tag, completed.stderr.decode('utf-8', 'replace').strip()))
    try:
        return completed.stdout.decode('utf-8')
    except UnicodeDecodeError as error:
        raise Failure('CHANGELOG.md at %s is not UTF-8: %s' % (tag, error))


def changelog_section(text, short_version, tag):
    """The section of CHANGELOG.md for `short_version`, at `tag` (3.6 step
    5). The heading's closing bracket is part of the match, so "3000.0.7"
    never matches a "3000.0.7-rc.1" heading or vice versa."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    lines = text.split('\n')
    heading = '## [%s]' % short_version

    start = next(
        (i for i, line in enumerate(lines) if line.startswith(heading)),
        None)
    if start is None:
        raise Failure(
            'CHANGELOG.md at %s has no "%s" heading' % (tag, heading))

    end = next(
        (i for i in range(start + 1, len(lines))
         if lines[i].startswith('## [')),
        len(lines))

    body_lines = [
        line for line in lines[start + 1:end]
        if line not in ('<!-- rc-temp -->', '<!-- /rc-temp -->')
    ]
    body = '\n'.join(body_lines)
    check_no_cdata_terminator(body)

    body = body.strip()
    if not body:
        raise Failure(
            'CHANGELOG.md at %s has an empty section for %s' % (tag, heading))
    return body


def download_dmg(url):
    """The released DMG, into a private temp file honoring $TMPDIR (3.6
    step 6). The caller unlinks it on every exit path."""
    try:
        response = urllib.request.urlopen(url)
    except urllib.error.HTTPError as error:
        raise Failure('GET %s failed: HTTP %d' % (url, error.code))
    except urllib.error.URLError as error:
        raise Failure('GET %s failed: %s' % (url, error.reason))

    with response:
        if response.status != 200:
            raise Failure('GET %s failed: HTTP %d' % (url, response.status))
        data = response.read()

    handle = tempfile.NamedTemporaryFile(delete=False)
    try:
        handle.write(data)
    finally:
        handle.close()
    return handle.name


def check_stapled(stapler, dmg_path):
    try:
        completed = subprocess.run(
            shlex.split(stapler) + ['validate', dmg_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as error:
        raise Failure('cannot run %s: %s' % (stapler, error))
    if completed.returncode != 0:
        raise Failure(
            'stapler validate failed on %s. Wait for the staple-release.yml '
            'workflow to finish, then check '
            'https://github.com/schuyler/macdown3000/actions.' % dmg_path)


def finish_publish(args, bundle_version, short_version, channel,
                   minimum_system_version, description, url, length,
                   signature):
    """Section 3.3: render the item, splice or create, validate once, then
    write or print it. Shared by explicit and release mode so neither
    reimplements the splice/validate/write story."""
    item = render_item(
        pub_date=format_datetime(datetime.now(timezone.utc)),
        bundle_version=bundle_version,
        short_version=short_version,
        channel=channel,
        minimum_system_version=minimum_system_version,
        description=description,
        url=url,
        length=length,
        signature=signature,
    )

    existed = os.path.exists(args.appcast)
    if existed:
        try:
            with open(args.appcast, encoding='utf-8', newline='') as handle:
                existing = handle.read()
        except (OSError, UnicodeDecodeError) as error:
            raise Failure('cannot read %s: %s' % (args.appcast, error))
        document = splice(existing, item)
    else:
        document = DOCUMENT_HEAD + item + DOCUMENT_TAIL

    validate(document, bundle_version, args.appcast, existed)

    if args.dry_run:
        # Through the buffer, so the document is UTF-8 whatever the locale
        # says -- it is the bytes a real run would write.
        sys.stdout.buffer.write(document.encode('utf-8'))
        sys.stdout.buffer.flush()
        return 0

    write_atomically(args.appcast, document)
    sys.stdout.write('appcast updated: %s (%s)\n'
                     % (bundle_version, short_version))
    return 0


def build_parser():
    parser = Parser(description='Add one release to the Sparkle appcast.')
    parser.add_argument('--release',
                        help='the published version to derive every '
                             'per-release input from, e.g. 3000.1.0')
    parser.add_argument('--appcast', default=DEFAULT_APPCAST,
                        help='the appcast to update, created if absent')
    parser.add_argument('--dmg',
                        help='the released DMG, downloaded from the GitHub '
                             'release after stapling -- never a local build')
    parser.add_argument('--url',
                        help='the https:// URL the DMG is served from')
    parser.add_argument('--description-file',
                        help='Markdown release notes for this version')
    parser.add_argument('--bundle-version',
                        help='CFBundleVersion from the app in the DMG')
    parser.add_argument('--short-version',
                        help='CFBundleShortVersionString from the same app')
    parser.add_argument('--minimum-system-version',
                        help='LSMinimumSystemVersion from the same app')
    parser.add_argument('--channel',
                        help='"beta" for a pre-release, "" for stable')
    parser.add_argument('--sign-update', default=DEFAULT_SIGN_UPDATE,
                        help='path to Sparkle\'s sign_update')
    parser.add_argument('--dry-run', action='store_true',
                        help='print the resulting document instead of '
                             'writing it; signs for real')
    parser.add_argument('--git', default=DEFAULT_GIT,
                        help='the git executable (--release mode)')
    parser.add_argument('--stapler', default=DEFAULT_STAPLER,
                        help='the stapler command, possibly with arguments '
                             '(--release mode)')
    parser.add_argument('--pbxproj', default=DEFAULT_PBXPROJ,
                        help='Xcode project file to read '
                             'MACOSX_DEPLOYMENT_TARGET from (--release mode)')
    parser.add_argument('--release-url-base', default=DEFAULT_RELEASE_URL_BASE,
                        help='GitHub release download base URL, used for '
                             'both the download and the enclosure URL '
                             '(--release mode)')
    return parser


def run_explicit(args):
    if args.channel is None:
        args.channel = ''
    check_arguments(args)
    description = read_description(args.description_file)
    key = sys.stdin.buffer.read()

    signature = sign(args.sign_update, args.dmg, key)

    return finish_publish(
        args, bundle_version=args.bundle_version,
        short_version=args.short_version, channel=args.channel,
        minimum_system_version=args.minimum_system_version,
        description=description, url=args.url,
        length=os.path.getsize(args.dmg), signature=signature)


def run_release(args):
    check_sign_update(args.sign_update)

    short_version, channel = release_version_and_channel(args.release)
    tag = 'v' + short_version

    resolve_tag(args.git, tag)
    bundle_version = bundle_version_for_tag(args.git, tag)
    minimum_system_version = minimum_system_version_from_pbxproj(
        args.pbxproj)
    description = changelog_section(
        changelog_for_tag(args.git, tag), short_version, tag)

    url = '%s/%s/MacDown-%s.dmg' % (args.release_url_base, tag, short_version)
    dmg_path = download_dmg(url)
    try:
        check_stapled(args.stapler, dmg_path)
        key = sys.stdin.buffer.read()
        signature = sign(args.sign_update, dmg_path, key)

        return finish_publish(
            args, bundle_version=bundle_version, short_version=short_version,
            channel=channel, minimum_system_version=minimum_system_version,
            description=description, url=url,
            length=os.path.getsize(dmg_path), signature=signature)
    finally:
        os.unlink(dmg_path)


def run(argv):
    args = build_parser().parse_args(argv)

    # Before anything else: an operator who forgets to pipe the key in should
    # get an error, not a process that waits forever.
    if sys.stdin.isatty():
        raise Failure('the signing key must be piped in on stdin, e.g. '
                      'op read "op://Personal/MacDown Sparkle EdDSA/password" '
                      '| %s ...' % os.path.basename(sys.argv[0]))

    if args.release is not None:
        check_release_conflicts(args)
        return run_release(args)

    check_required_explicit_arguments(args)
    return run_explicit(args)


def main(argv):
    try:
        return run(argv)
    except Failure as error:
        sys.stderr.write('%s: %s\n' % (os.path.basename(sys.argv[0]), error))
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
