#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests for Tools/update_appcast.py.

Run: python3 Tools/test_update_appcast.py

The script under test is exercised as a subprocess, because its contract is a
CLI contract: argv, stdin, exit code, stdout, stderr, and the bytes it leaves
on disk.

`sign_update` is always a generated stub. The real Sparkle `sign_update`
rewrites XML files in place when handed one, so nothing here may point it at a
test fixture -- or at anything else.
"""

import base64
import email.utils
import glob
import os
import pty
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone


ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT_DIR, 'Tools', 'update_appcast.py')

SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
SP = '{%s}' % SPARKLE_NS

# A well-formed Ed25519 signature in base64: 64 bytes -> 88 chars ending "==".
STUB_SIGNATURE = (
    'Ov9k2mQ3H1cVYxTn0aQ8pLpQ4bK7dR2sYy1uWw6cJ0nZ'
    '8rT5fXhE3mB7oQdA1cV2sYy1uWw6cJ0nZ8rT5fXhEg=='
)

# 32-byte seed, 44 base64 chars, as generate_keys -x exports.
STUB_KEY = base64.b64encode(b'k' * 32).decode('ascii') + '\n'

DEFAULT_SIGN_UPDATE = 'Pods/Sparkle/bin/sign_update'

DEFAULT_URL = ('https://github.com/schuyler/macdown3000/releases/download/'
               'v3000.1.0/MacDown-3000.1.0.dmg')

DEFAULT_DESCRIPTION = '### Added\n\n- Automate the appcast (#554)'


def expected_item(pub_date, bundle_version='4837', short_version='3000.1.0',
                  channel='', minimum='11.0',
                  description=DEFAULT_DESCRIPTION, url=DEFAULT_URL,
                  length='4096', signature=STUB_SIGNATURE):
    """The exact bytes of one rendered item (section 3.1). Used on both the
    create path and the splice path, so neither can drift from the other."""
    channel_line = ''
    if channel:
        channel_line = (
            '      <sparkle:channel>%s</sparkle:channel>\n' % channel)
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
        '      <enclosure url="%s" length="%s" '
        'type="application/octet-stream" sparkle:edSignature="%s"/>\n'
        '    </item>\n'
    ) % (short_version, pub_date, bundle_version, short_version, channel_line,
         minimum, description, url, length, signature)


def mask_pub_dates(text):
    return re.sub(r'<pubDate>[^<]*</pubDate>', '<pubDate>-</pubDate>', text)


def first_pub_date(text):
    found = re.search(r'<pubDate>([^<]+)</pubDate>', text)
    assert found is not None, 'no pubDate in:\n' + text
    return found.group(1)

EXPECTED_HEADER = (
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

EXPECTED_FOOTER = '  </channel>\n</rss>\n'


def existing_feed(items=''):
    """A feed the script did not write, carrying the ElementTree hazards of
    section 2.4 -- a comment, a processing instruction, CDATA with a raw
    ampersand, non-ASCII text -- plus one CRLF line, which a universal-newlines
    read would silently rewrite (D1 forbids touching existing bytes)."""
    return (
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<?xml-stylesheet type="text/xsl" href="appcast.xsl"?>\n'
        '<rss version="2.0" xmlns:sparkle="%s">\n'
        '  <channel>\n'
        '    <title>MacDown 3000</title>\n'
        '    <!-- hand-written, do not reformat -->\n'
        '%s'
        '  </channel>\n'
        '</rss>\n'
    ) % (SPARKLE_NS, items)


def existing_item(bundle_version='1000', short_version='3000.0.9'):
    return (
        '    <item>\n'
        '      <title>MacDown 3000 %s — versión antigua</title>\n'
        '      <sparkle:version>%s</sparkle:version>\n'
        '      <description sparkle:format="markdown"><![CDATA[\n'
        'Fixed A & B <not a tag>\n'
        ']]></description>\n'
        '    </item>\n'
    ) % (short_version, bundle_version)


class AppcastTestCase(unittest.TestCase):
    """Fixture: a temp dir holding a fake DMG, a description file, and a stub
    sign_update that records how it was called."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='appcast-test-')
        self.addCleanup(shutil.rmtree, self.tmp, True)

        self.appcast = os.path.join(self.tmp, 'docs', 'sparkle', 'appcast.xml')
        self.dmg = os.path.join(self.tmp, 'MacDown-3000.1.0.dmg')
        with open(self.dmg, 'wb') as f:
            f.write(b'\x00' * 4096)

        self.description = os.path.join(self.tmp, 'section.md')
        self.write_description('### Added\n\n- Automate the appcast (#554)\n')

        self.argv_log = os.path.join(self.tmp, 'sign_update.argv')
        self.stdin_log = os.path.join(self.tmp, 'sign_update.stdin')
        self.env_log = os.path.join(self.tmp, 'sign_update.env')
        self.scan_log = os.path.join(self.tmp, 'sign_update.scan')
        self.sign_update = self.make_sign_update()

    # -- fixture helpers --------------------------------------------------

    def write_description(self, text):
        with open(self.description, 'w', encoding='utf-8') as f:
            f.write(text)

    def make_sign_update(self, stdout=STUB_SIGNATURE + '\n', returncode=0,
                         name='sign_update', executable=True):
        """A stub standing in for Sparkle's sign_update.

        Records its argv (one argument per line), its environment, and its
        stdin, and lists any file under the temp dir that already holds the
        key. Empty stdin is an error that exits non-zero and prints nothing,
        which is what section 2.1 records the real tool doing.
        """
        def quote(value):
            return "'" + value.replace("'", "'\\''") + "'"

        # Recording paths and output are baked in, so the stub never depends
        # on the environment the script under test hands to the subprocess.
        body = (
            '#!/bin/sh\n'
            'for a in "$@"; do printf "%s\\n" "$a"; done > ' + quote(
                self.argv_log) + '\n'
            'env > ' + quote(self.env_log) + '\n'
            # Clear the previous invocation's stdin capture first, or a second
            # signing finds that and reports the key as loose on disk.
            'rm -f ' + quote(self.stdin_log) + '\n'
            'grep -rlF ' + quote(STUB_KEY.strip()) + ' ' + quote(self.tmp)
            + ' > ' + quote(self.scan_log) + ' 2>/dev/null\n'
            'cat > ' + quote(self.stdin_log) + '\n'
            'if [ ! -s ' + quote(self.stdin_log) + ' ]; then exit 1; fi\n'
            'printf "%s" ' + quote(stdout) + '\n'
            'exit ' + str(returncode) + '\n'
        )
        path = os.path.join(self.tmp, name)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(body)
        os.chmod(path, 0o755 if executable else 0o644)
        return path

    def write_appcast(self, text):
        os.makedirs(os.path.dirname(self.appcast), exist_ok=True)
        with open(self.appcast, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        return self.read_appcast()

    def read_appcast(self):
        with open(self.appcast, 'rb') as f:
            return f.read()

    # -- invocation -------------------------------------------------------

    def run_script(self, extra=None, key=STUB_KEY, cwd=None, stdin_tty=False,
                   env=None, **overrides):
        args = {
            '--appcast': self.appcast,
            '--dmg': self.dmg,
            '--url': ('https://github.com/schuyler/macdown3000/releases/'
                      'download/v3000.1.0/MacDown-3000.1.0.dmg'),
            '--description-file': self.description,
            '--bundle-version': '4837',
            '--short-version': '3000.1.0',
            '--minimum-system-version': '11.0',
            '--channel': '',
            '--sign-update': self.sign_update,
        }
        args.update(overrides)

        argv = [sys.executable, SCRIPT]
        for flag, value in args.items():
            if value is None:
                continue
            argv += [flag, value]
        argv += extra or []

        # Captured as bytes and decoded here, not with text=True: universal
        # newline translation would turn a CR the script faithfully preserved
        # into an LF, and the dry-run tests compare stdout to the file's bytes.
        if stdin_tty:
            master, slave = pty.openpty()
            try:
                proc = subprocess.run(
                    argv, stdin=slave, capture_output=True,
                    cwd=cwd or self.tmp, timeout=30,
                )
            finally:
                os.close(slave)
                os.close(master)
        else:
            proc = subprocess.run(
                argv, input=key.encode('utf-8'), capture_output=True,
                cwd=cwd or self.tmp, timeout=30,
                env=dict(os.environ, **env) if env else None,
            )
        return subprocess.CompletedProcess(
            proc.args, proc.returncode,
            proc.stdout.decode('utf-8'), proc.stderr.decode('utf-8'),
        )

    def publish(self, **kwargs):
        proc = self.run_script(**kwargs)
        self.assertEqual(
            proc.returncode, 0,
            'expected success\nstdout: %s\nstderr: %s'
            % (proc.stdout, proc.stderr),
        )
        return proc

    # -- assertions -------------------------------------------------------

    def item_elements(self, xml_bytes=None):
        if xml_bytes is None:
            xml_bytes = self.read_appcast()
        root = ET.fromstring(xml_bytes)
        return root.findall('./channel/item')

    def sole_item(self, xml_bytes=None):
        items = self.item_elements(xml_bytes)
        self.assertEqual(len(items), 1, 'expected exactly one item')
        return items[0]

    def assert_pure_insertion(self, original, result, why=None):
        """`result` must be `original` with one contiguous block inserted --
        no existing byte rewritten (D1)."""
        why = why or 'existing bytes were rewritten, not spliced around'
        limit = min(len(original), len(result))
        prefix = 0
        while prefix < limit and original[prefix] == result[prefix]:
            prefix += 1
        suffix = 0
        while (suffix < limit - prefix
               and original[-1 - suffix] == result[-1 - suffix]):
            suffix += 1
        self.assertEqual(prefix + suffix, len(original), why)
        self.assertGreater(len(result), len(original))

    def assert_unchanged(self, before):
        self.assertEqual(self.read_appcast(), before, 'file was modified')

    def assert_no_temp_files(self):
        directory = os.path.dirname(self.appcast)
        if not os.path.isdir(directory):
            return
        leftovers = [
            n for n in os.listdir(directory)
            if n != os.path.basename(self.appcast)
        ]
        self.assertEqual(leftovers, [], 'temp file left behind')


class TestRenderedItem(AppcastTestCase):
    """Section 3.1 -- the item the script renders."""

    def test_first_run_writes_the_whole_document_verbatim(self):
        self.publish()
        text = self.read_appcast().decode('utf-8')

        expected = (EXPECTED_HEADER + expected_item(first_pub_date(text))
                    + EXPECTED_FOOTER)
        self.assertEqual(text, expected)

    def test_first_run_creates_parent_directories(self):
        self.assertFalse(os.path.isdir(os.path.dirname(self.appcast)))
        self.publish()
        self.assertTrue(os.path.isfile(self.appcast))

    def test_file_is_utf8_without_bom_and_lf_only(self):
        self.write_description('### Añadido\n\n- Soporte de «actualización»\n')
        self.publish()
        raw = self.read_appcast()
        self.assertFalse(raw.startswith(b'\xef\xbb\xbf'), 'BOM present')
        self.assertNotIn(b'\r', raw)
        self.assertIn('«actualización»'.encode('utf-8'), raw)
        raw.decode('utf-8')

    def test_child_order_is_exact_for_a_prerelease(self):
        self.publish(**{'--channel': 'beta'})
        item = self.sole_item()
        self.assertEqual(
            [child.tag for child in item],
            [
                'title',
                'pubDate',
                SP + 'version',
                SP + 'shortVersionString',
                SP + 'channel',
                SP + 'minimumSystemVersion',
                'description',
                'enclosure',
            ],
        )

    def test_beta_channel_element_is_emitted_for_prereleases(self):
        self.publish(**{'--channel': 'beta'})
        self.assertEqual(self.sole_item().findtext(SP + 'channel'), 'beta')

    def test_prerelease_item_bytes_are_exact(self):
        self.publish(**{'--channel': 'beta'})
        text = self.read_appcast().decode('utf-8')
        self.assertEqual(
            text,
            EXPECTED_HEADER
            + expected_item(first_pub_date(text), channel='beta')
            + EXPECTED_FOOTER,
        )

    def test_stable_item_omits_the_channel_element(self):
        self.publish(**{'--channel': ''})
        self.assertIsNone(self.sole_item().find(SP + 'channel'))
        self.assertNotIn(b'sparkle:channel', self.read_appcast())

    def test_channel_defaults_to_stable_when_flag_absent(self):
        self.publish(**{'--channel': None})
        self.assertIsNone(self.sole_item().find(SP + 'channel'))

    def test_versions_and_minimum_system_version(self):
        self.publish()
        item = self.sole_item()
        self.assertEqual(item.findtext(SP + 'version'), '4837')
        self.assertEqual(item.findtext(SP + 'shortVersionString'), '3000.1.0')
        self.assertEqual(item.findtext(SP + 'minimumSystemVersion'), '11.0')

    def test_title_names_the_app_and_short_version(self):
        self.publish()
        self.assertEqual(
            self.sole_item().findtext('title'), 'MacDown 3000 3000.1.0')

    def test_pubdate_is_rfc5322_utc_and_current(self):
        self.publish()
        raw = self.sole_item().findtext('pubDate')
        self.assertTrue(raw.endswith('+0000'), raw)
        parsed = email.utils.parsedate_to_datetime(raw)
        self.assertEqual(parsed.utcoffset(), timedelta(0))
        self.assertLess(
            abs(datetime.now(timezone.utc) - parsed), timedelta(minutes=5))

    def test_enclosure_attributes(self):
        self.publish()
        enclosure = self.sole_item().find('enclosure')
        self.assertEqual(
            enclosure.get('url'),
            'https://github.com/schuyler/macdown3000/releases/download/'
            'v3000.1.0/MacDown-3000.1.0.dmg',
        )
        self.assertEqual(enclosure.get('type'), 'application/octet-stream')
        self.assertEqual(enclosure.get(SP + 'edSignature'), STUB_SIGNATURE)

    def test_enclosure_length_is_the_dmg_size_on_disk(self):
        with open(self.dmg, 'wb') as f:
            f.write(b'x' * 1234567)
        self.publish()
        length = self.sole_item().find('enclosure').get('length')
        self.assertEqual(length, '1234567')
        self.assertEqual(int(length), os.path.getsize(self.dmg))

    def test_omits_guid_link_and_installation_type(self):
        self.publish(**{'--channel': 'beta'})
        item = self.sole_item()
        self.assertIsNone(item.find('guid'))
        self.assertIsNone(item.find('link'))
        self.assertIsNone(item.find(SP + 'informationalUpdate'))
        self.assertNotIn(b'sparkle:installationType', self.read_appcast())

    def test_description_format_attribute_is_sparkle_format_markdown(self):
        self.publish()
        raw = self.read_appcast()
        self.assertIn(b'<description sparkle:format="markdown">', raw)
        self.assertNotIn(b'descriptionFormat', raw)

    def test_cdata_body_is_bracketed_by_exactly_one_newline_each_side(self):
        self.write_description('\n\n\n### Added\n\n- One thing\n\n\n')
        self.publish()
        raw = self.read_appcast().decode('utf-8')
        self.assertIn(
            '<![CDATA[\n### Added\n\n- One thing\n]]></description>', raw)

    def test_description_special_characters_pass_through_cdata_verbatim(self):
        self.write_description('A & B <tag> "quoted" \'single\'\n')
        self.publish()
        self.assertIn(
            b'<![CDATA[\nA & B <tag> "quoted" \'single\'\n]]>',
            self.read_appcast(),
        )
        self.assertEqual(
            self.sole_item().findtext('description').strip(),
            'A & B <tag> "quoted" \'single\'',
        )

    def test_carriage_returns_in_the_description_are_normalized(self):
        self.write_description('### Added\r\n\r\n- CRLF line\r- CR line\r\n')
        self.publish()
        raw = self.read_appcast()
        self.assertNotIn(b'\r', raw)
        self.assertIn(b'- CRLF line\n- CR line', raw)


class TestSplicing(AppcastTestCase):
    """Section 3.3 steps 1-3 -- insert, never re-emit (D1)."""

    def test_splices_before_the_first_existing_item(self):
        before = self.write_appcast(
            existing_feed(existing_item('1000') + existing_item('999')))
        self.publish()
        after = self.read_appcast()

        self.assert_pure_insertion(before, after)
        versions = [
            item.findtext(SP + 'version') for item in self.item_elements()]
        self.assertEqual(versions, ['4837', '1000', '999'])

    def test_preserves_comments_processing_instructions_and_raw_cdata(self):
        before = self.write_appcast(existing_feed(existing_item()))
        self.publish()
        after = self.read_appcast()

        self.assertIn(b'<?xml-stylesheet type="text/xsl" '
                      b'href="appcast.xsl"?>', after)
        self.assertIn(b'<!-- hand-written, do not reformat -->', after)
        self.assertIn(b'Fixed A & B <not a tag>', after)
        self.assertIn('versión antigua'.encode('utf-8'), after)
        self.assert_pure_insertion(before, after)

    def test_splices_before_the_channel_close_when_there_are_no_items(self):
        before = self.write_appcast(existing_feed())
        self.publish()
        after = self.read_appcast()
        self.assert_pure_insertion(before, after)
        self.assertEqual(len(self.item_elements()), 1)

    def test_two_successive_releases(self):
        """The primary workflow: the second publish splices into the file the
        first one wrote, rather than into a hand-written fixture."""
        self.publish()
        first = self.read_appcast()

        self.write_description('### Fixed\n\n- A later release\n')
        self.publish(**{'--bundle-version': '4838',
                        '--short-version': '3000.1.1'})
        second = self.read_appcast()

        self.assert_pure_insertion(first, second)

        # The spliced item must be byte-identical to what the create path
        # renders. Splicing is a text operation (D1), so nothing else forces
        # the two paths to share a renderer.
        text = second.decode('utf-8')
        self.assertIn(
            expected_item(first_pub_date(text), bundle_version='4838',
                          short_version='3000.1.1',
                          description='### Fixed\n\n- A later release'),
            text,
        )
        self.assertEqual(
            [item.findtext(SP + 'version') for item in self.item_elements()],
            ['4838', '4837'],
        )
        self.assertEqual(
            [item.findtext(SP + 'shortVersionString')
             for item in self.item_elements()],
            ['3000.1.1', '3000.1.0'],
        )

    def test_splicing_into_a_feed_without_the_namespace_is_refused(self):
        """Our item uses sparkle: prefixes, so an undeclared prefix makes the
        result unparseable -- caught by the single validating parse."""
        # No existing items, so the undeclared prefix can only come from the
        # item we insert -- otherwise this just repeats the malformed-file
        # case, since existing_item() is itself sparkle:-prefixed.
        before = self.write_appcast(
            existing_feed().replace(' xmlns:sparkle="%s"' % SPARKLE_NS, ''))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)
        self.assert_no_temp_files()

    def test_exits_1_when_neither_anchor_is_found(self):
        before = self.write_appcast(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<rss version="2.0" xmlns:sparkle="%s"><channel>'
            '<title>MacDown 3000</title></channel></rss>\n' % SPARKLE_NS)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)
        self.assert_no_temp_files()


class TestValidation(AppcastTestCase):
    """Section 3.3 step 4 -- one validating parse of the result."""

    def test_duplicate_bundle_version_is_refused(self):
        self.publish()
        before = self.read_appcast()

        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)
        self.assert_no_temp_files()

    def test_duplicate_error_tells_the_operator_how_to_recover(self):
        self.publish()
        proc = self.run_script()
        message = proc.stderr.lower()
        self.assertIn('4837', proc.stderr)
        self.assertIn('item', message)
        self.assertIn('delete', message)

    def test_duplicate_is_refused_even_with_a_different_short_version(self):
        """A #564 collision between release branches: same commit-count
        CFBundleVersion, different releases. Replacing the item would push a
        wrong download URL to every install."""
        self.publish(**{'--short-version': '3000.0.7'})
        before = self.read_appcast()
        proc = self.run_script(**{'--short-version': '3000.1.0'})
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)

    def test_preexisting_duplicate_in_the_feed_is_refused(self):
        before = self.write_appcast(
            existing_feed(existing_item('4837') + existing_item('4837')))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)

    def test_malformed_existing_file_is_refused(self):
        before = self.write_appcast(
            existing_feed(existing_item()).replace('</channel>', ''))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)
        self.assert_no_temp_files()

    def test_malformed_existing_file_message_names_the_ambiguity(self):
        self.write_appcast(
            existing_feed(existing_item()).replace('<title>', '<title'))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        # The script cannot tell a corrupt splice from a file that arrived
        # broken, so the message has to name both possibilities (3.3).
        message = proc.stderr.lower()
        self.assertIn('existing', message)
        self.assertIn('already', message)

    def test_control_character_in_the_description_is_refused(self):
        self.write_description('### Added\n\n- A form feed \x0c here\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assertFalse(os.path.exists(self.appcast))

    def test_ampersand_in_the_url_survives_a_round_trip(self):
        url = 'https://example.com/d?a=1&b=2&amp;c=3'
        self.publish(**{'--url': url})
        self.assertNotIn(b'a=1&b=2', self.read_appcast())
        self.assertEqual(self.sole_item().find('enclosure').get('url'), url)

    def test_double_quote_in_an_attribute_keeps_double_quote_delimiters(self):
        """saxutils.quoteattr would switch to single quotes here (3.4)."""
        url = 'https://example.com/a"b.dmg'
        self.publish(**{'--url': url})
        self.assertIn(b'url="https://example.com/a&quot;b.dmg"',
                      self.read_appcast())
        self.assertNotIn(b'&amp;quot;', self.read_appcast())
        self.assertEqual(self.sole_item().find('enclosure').get('url'), url)

    def test_markup_in_the_short_version_is_escaped_in_element_text(self):
        self.publish(**{'--short-version': '3000.1.0<&>'})
        self.assertIn(b'3000.1.0&lt;&amp;&gt;', self.read_appcast())
        self.assertEqual(
            self.sole_item().findtext(SP + 'shortVersionString'),
            '3000.1.0<&>',
        )


class TestArgumentValidation(AppcastTestCase):
    """Section 3.2."""

    def assert_refused_before_signing(self, before=None, **overrides):
        """Both guards in 3.3 exist to keep sign_update away from the file, so
        exiting 1 is not enough -- the subprocess must never have run.

        Checked in both modes. Section 4 step 4 has the operator append
        --dry-run to the publish command and run that first, so a dry run is
        where a --dmg/--appcast slip in a freshly typed command line lands.
        A guard that only fires on the write path is no guard at all.
        """
        for mode in ([], ['--dry-run']):
            with self.subTest(mode=mode[0] if mode else 'real'):
                proc = self.run_script(extra=mode, **overrides)
                self.assertEqual(proc.returncode, 1, proc.stderr)
                self.assertFalse(
                    os.path.exists(self.stdin_log),
                    'sign_update was launched before the check')
                self.assertFalse(
                    os.path.exists(self.argv_log),
                    'sign_update was launched before the check')
                if before is not None:
                    self.assert_unchanged(before)
        return proc

    def test_missing_dmg_is_refused(self):
        self.assert_refused_before_signing(
            **{'--dmg': os.path.join(self.tmp, 'absent.dmg')})
        self.assertFalse(os.path.exists(self.appcast))

    def test_non_dmg_extension_is_refused(self):
        """An operator who types some other XML path into --dmg must not reach
        sign_update, which would rewrite that file in place and exit 0."""
        for name, content in (('MacDown.zip', b'zip'),
                              ('other-feed.xml', b'<rss/>'),
                              ('MacDown.dmg.txt', b'text')):
            with self.subTest(name=name):
                other = os.path.join(self.tmp, name)
                with open(other, 'wb') as f:
                    f.write(content)
                self.assert_refused_before_signing(**{'--dmg': other})

    def test_dmg_naming_the_appcast_is_refused(self):
        """sign_update handed an XML file embeds the signature inside it,
        rewriting the feed in place and exiting 0 (3.3)."""
        before = self.write_appcast(existing_feed(existing_item()))
        self.assert_refused_before_signing(
            before, **{'--dmg': self.appcast})

    def test_dmg_equal_to_the_appcast_is_refused_even_when_named_dmg(self):
        """Isolates the same-path guard from the extension guard: here the
        extension check passes, so only the path comparison can refuse."""
        self.appcast = os.path.join(self.tmp, 'docs', 'feed.dmg')
        before = self.write_appcast(existing_feed(existing_item()))
        self.assert_refused_before_signing(
            before, **{'--dmg': self.appcast})

    def test_dmg_reaching_the_appcast_by_a_relative_path_is_refused(self):
        """Same file, different spelling. The extension guard cannot catch
        this one, so the comparison must normalize the paths."""
        self.appcast = os.path.join(self.tmp, 'docs', 'feed.dmg')
        before = self.write_appcast(existing_feed(existing_item()))
        directory, name = os.path.split(self.appcast)
        indirect = os.path.join(directory, '.', '..', 'docs', name)
        self.assert_refused_before_signing(before, **{'--dmg': indirect})

    def test_dmg_symlinked_to_the_appcast_is_refused(self):
        """A symlink named *.dmg passes the extension guard and spells a
        different path, so only realpath resolution refuses it."""
        self.appcast = os.path.join(self.tmp, 'docs', 'feed.dmg')
        before = self.write_appcast(existing_feed(existing_item()))
        link = os.path.join(self.tmp, 'sneaky.dmg')
        os.symlink(self.appcast, link)
        self.assert_refused_before_signing(before, **{'--dmg': link})

    def test_dmg_hardlinked_to_the_appcast_is_refused(self):
        """realpath does not resolve hard links, so refusing this one needs
        os.path.samefile -- and the guard exists to keep sign_update away from
        the feed's inode, not from a spelling of its name."""
        self.appcast = os.path.join(self.tmp, 'docs', 'feed.dmg')
        before = self.write_appcast(existing_feed(existing_item()))
        link = os.path.join(self.tmp, 'hard.dmg')
        os.link(self.appcast, link)
        self.assert_refused_before_signing(before, **{'--dmg': link})

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0,
                     'root ignores file permissions')
    def test_unreadable_dmg_is_refused(self):
        os.chmod(self.dmg, 0o000)
        self.addCleanup(os.chmod, self.dmg, 0o644)
        self.assert_refused_before_signing()
        self.assertFalse(os.path.exists(self.appcast))

    def test_required_arguments_are_enforced(self):
        """Section 3.5 gives one failure exit code for everything, so a
        missing flag must not surface argparse's usage exit of 2."""
        for flag in ('--appcast', '--dmg', '--url', '--description-file',
                     '--bundle-version', '--short-version',
                     '--minimum-system-version'):
            with self.subTest(flag=flag):
                proc = self.run_script(**{flag: None})
                self.assertEqual(proc.returncode, 1, proc.stderr)

    def test_non_https_url_is_refused(self):
        for url in ('http://example.com/a.dmg', 'file:///tmp/a.dmg',
                    'example.com/a.dmg'):
            with self.subTest(url=url):
                proc = self.run_script(**{'--url': url})
                self.assertEqual(proc.returncode, 1)

    def test_unknown_channel_is_refused(self):
        """Exit 1, not argparse's 2: section 3.5 says every error exits 1."""
        for channel in ('alpha', 'stable', 'Beta'):
            with self.subTest(channel=channel):
                proc = self.run_script(**{'--channel': channel})
                self.assertEqual(proc.returncode, 1, proc.stderr)

    def test_bundle_version_character_set_is_enforced(self):
        for version in ('48 37', '48/37', '', '4837;rm'):
            with self.subTest(version=version):
                proc = self.run_script(**{'--bundle-version': version})
                self.assertEqual(proc.returncode, 1, proc.stderr)

    def test_bundle_version_allows_dots_dashes_and_underscores(self):
        self.publish(**{'--bundle-version': '4837.1_a-b'})
        self.assertEqual(
            self.sole_item().findtext(SP + 'version'), '4837.1_a-b')

    def test_url_containing_whitespace_is_refused(self):
        """XML attribute-value normalization would hide it from the operator
        reading the --dry-run output, and every download would 404."""
        for url in ('https://example.com/a.dmg ',
                    ' https://example.com/a.dmg',
                    'https://example.com/a\tb.dmg',
                    'https://example.com/a\nb.dmg'):
            with self.subTest(url=repr(url)):
                proc = self.run_script(**{'--url': url})
                self.assertEqual(proc.returncode, 1, proc.stderr)

    def test_non_utf8_description_file_is_refused_cleanly(self):
        with open(self.description, 'wb') as f:
            f.write(b'### Added\n\n- Latin-1 \xe1cute\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertFalse(os.path.exists(self.appcast))

    def test_empty_version_fields_are_refused(self):
        """PlistBuddy yields an empty string for a missing key, and the
        documented procedure feeds its output straight into these flags."""
        for flag in ('--short-version', '--minimum-system-version'):
            for value in ('', '   '):
                with self.subTest(flag=flag, value=repr(value)):
                    proc = self.run_script(**{flag: value})
                    self.assertEqual(proc.returncode, 1, proc.stderr)
                    self.assertFalse(os.path.exists(self.appcast))

    def test_missing_description_file_is_refused(self):
        proc = self.run_script(
            **{'--description-file': os.path.join(self.tmp, 'absent.md')})
        self.assertEqual(proc.returncode, 1)

    def test_blank_description_file_is_refused(self):
        for text in ('', '\n\n', '   \t\n  \n'):
            with self.subTest(text=repr(text)):
                self.write_description(text)
                proc = self.run_script()
                self.assertEqual(proc.returncode, 1)

    def test_description_containing_a_cdata_terminator_is_refused(self):
        self.write_description(
            '### Added\n\n- A line\n- Ends the section ]]> right here\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assertIn('Ends the section ]]> right here', proc.stderr)
        self.assertFalse(os.path.exists(self.appcast))

    def test_missing_sign_update_is_refused_and_names_the_path(self):
        missing = os.path.join(self.tmp, 'nope', 'sign_update')
        proc = self.run_script(**{'--sign-update': missing})
        self.assertEqual(proc.returncode, 1)
        self.assertIn(missing, proc.stderr)

    def test_non_executable_sign_update_is_refused_and_names_the_path(self):
        path = self.make_sign_update(name='not_exec', executable=False)
        proc = self.run_script(**{'--sign-update': path})
        self.assertEqual(proc.returncode, 1)
        self.assertIn(path, proc.stderr)

    def test_sign_update_defaults_to_the_cocoapods_path(self):
        """Resolved against the working directory, so this run cannot reach
        the repo's real sign_update -- which would rewrite an XML file handed
        to it in place."""
        proc = self.run_script(**{'--sign-update': None})
        self.assertEqual(proc.returncode, 1)
        self.assertIn(DEFAULT_SIGN_UPDATE, proc.stderr)
        self.assertNotIn(ROOT_DIR, proc.stderr)


class TestSigning(AppcastTestCase):
    """Sections 3.3 and 3.5 -- the signing subprocess and the key."""

    def recorded_argv(self):
        with open(self.argv_log, encoding='utf-8') as f:
            return f.read().splitlines()

    def recorded_stdin(self):
        with open(self.stdin_log, encoding='utf-8') as f:
            return f.read()

    def test_key_is_passed_on_stdin_and_never_in_argv(self):
        self.publish()
        argv = self.recorded_argv()
        self.assertIn('-p', argv)
        self.assertIn('--ed-key-file', argv)
        self.assertIn('-', argv)
        self.assertEqual(self.recorded_stdin(), STUB_KEY)
        for argument in argv:
            self.assertNotIn(STUB_KEY.strip(), argument)

    def test_sign_update_is_given_the_dmg(self):
        self.publish()
        self.assertIn(self.dmg, self.recorded_argv())
        self.assertNotIn(self.appcast, self.recorded_argv())

    def test_key_is_not_leaked_to_stdout_or_stderr(self):
        proc = self.publish()
        self.assertNotIn(STUB_KEY.strip(), proc.stdout)
        self.assertNotIn(STUB_KEY.strip(), proc.stderr)

    def test_key_is_not_placed_in_the_subprocess_environment(self):
        self.publish()
        with open(self.env_log, encoding='utf-8', errors='replace') as f:
            self.assertNotIn(STUB_KEY.strip(), f.read())

    def test_key_is_not_written_to_a_temp_file(self):
        """The stub scans for the key while the script is still running, so a
        temp file unlinked afterwards is still caught."""
        self.publish()
        with open(self.scan_log, encoding='utf-8') as f:
            holders = [line for line in f.read().splitlines() if line]
        # The stub carries the key itself, to grep for it.
        holders = [p for p in holders
                   if os.path.realpath(p) != os.path.realpath(
                       self.sign_update)]
        self.assertEqual(holders, [], 'key found on disk during signing')

    def assert_signature_refused(self, stdout, returncode=0):
        """Checked in both modes: 3.5 says --dry-run returns the exit code the
        real run would have, so a bad key is caught in the pre-flight rather
        than after it."""
        self.sign_update = self.make_sign_update(
            stdout=stdout, returncode=returncode)
        for mode in ([], ['--dry-run']):
            with self.subTest(mode=mode[0] if mode else 'real'):
                proc = self.run_script(extra=mode)
                self.assertEqual(proc.returncode, 1, proc.stdout)
                self.assertFalse(os.path.exists(self.appcast))

    def test_empty_signature_is_refused_despite_exit_0(self):
        for output in ('', '\n', '   \n\t\n'):
            with self.subTest(output=repr(output)):
                self.assert_signature_refused(output)

    def test_non_base64_signature_is_refused_despite_exit_0(self):
        for output in ('not base64!!\n', 'sig with spaces\n', '****\n',
                       'abc==def\n'):
            with self.subTest(output=repr(output)):
                self.assert_signature_refused(output)

    def test_sign_update_failure_is_refused(self):
        self.assert_signature_refused('', returncode=1)

    def test_sign_update_exit_code_is_checked_even_with_valid_output(self):
        """Pairs a non-zero exit with a well-formed signature, so passing
        requires reading the exit code -- the base64 guard cannot cover it."""
        self.assert_signature_refused(STUB_SIGNATURE + '\n', returncode=1)

    def test_base64_guard_is_checked_even_with_exit_0(self):
        """The mirror image: exit 0 is not evidence a signature exists."""
        self.assert_signature_refused('not a signature\n')

    def test_wrong_length_signature_is_refused(self):
        """Valid base64 of the wrong size is not an Ed25519 signature, which
        is always 64 bytes."""
        for size in (32, 63, 65, 96):
            with self.subTest(size=size):
                self.assert_signature_refused(
                    base64.b64encode(b's' * size).decode('ascii') + '\n')

    def test_correct_length_signature_is_accepted(self):
        self.assertEqual(len(base64.b64decode(STUB_SIGNATURE)), 64)
        self.publish()
        self.assertEqual(
            self.sole_item().find('enclosure').get(SP + 'edSignature'),
            STUB_SIGNATURE)

    def test_signature_is_stripped_of_the_trailing_newline(self):
        self.publish()
        self.assertEqual(
            self.sole_item().find('enclosure').get(SP + 'edSignature'),
            STUB_SIGNATURE,
        )

    def test_empty_key_on_stdin_is_refused(self):
        """sign_update itself rejects empty stdin (2.1); the script must
        propagate that rather than publishing an unsigned item."""
        proc = self.run_script(key='')
        self.assertEqual(proc.returncode, 1)
        self.assertFalse(os.path.exists(self.appcast))

    def test_tty_stdin_is_refused_instead_of_blocking(self):
        proc = self.run_script(stdin_tty=True)
        self.assertEqual(proc.returncode, 1)
        self.assertIn('stdin', proc.stderr.lower())
        self.assertFalse(os.path.exists(self.appcast))


class TestOutput(AppcastTestCase):
    """Section 3.5."""

    def test_success_message_and_exit_code(self):
        proc = self.publish()
        self.assertEqual(
            proc.stdout.strip(), 'appcast updated: 4837 (3000.1.0)')

    def test_atomic_write_leaves_no_temp_file(self):
        self.publish()
        self.assert_no_temp_files()

    def test_published_file_is_world_readable(self):
        """mkstemp creates 0600 and os.replace would carry that onto a feed
        GitHub Pages serves."""
        self.publish()
        self.assertEqual(os.stat(self.appcast).st_mode & 0o777, 0o644)

    def test_dry_run_emits_utf8_whatever_the_locale_says(self):
        self.write_description('### Añadido\n\n- Soporte de «actualización»\n')
        proc = self.publish(extra=['--dry-run'], env={'LC_ALL': 'C',
                                                      'LANG': 'C',
                                                      'PYTHONUTF8': '0',
                                                      'PYTHONCOERCECLOCALE':
                                                      '0'})
        self.assertIn('«actualización»', proc.stdout)

    @unittest.skipIf(hasattr(os, 'geteuid') and os.geteuid() == 0,
                     'root ignores directory permissions')
    def test_unwritable_directory_leaves_the_file_byte_identical(self):
        """Proxy for the atomic write (3.3 step 5): the temp file lands beside
        the target, so an undoable directory fails before os.replace()."""
        before = self.write_appcast(existing_feed(existing_item()))
        directory = os.path.dirname(self.appcast)
        os.chmod(directory, 0o500)
        self.addCleanup(os.chmod, directory, 0o755)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)

    def test_failure_leaves_the_file_byte_identical(self):
        before = self.write_appcast(existing_feed(existing_item('4837')))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)
        self.assert_no_temp_files()

    def test_dry_run_prints_the_document_and_touches_no_file(self):
        proc = self.publish(extra=['--dry-run'])
        self.assertFalse(os.path.exists(self.appcast))
        self.assertFalse(os.path.isdir(os.path.dirname(self.appcast)),
                         'dry run created the parent directory')
        self.assertTrue(proc.stdout.startswith('<?xml version="1.0"'))
        # Exactly the document, with nothing appended -- not print(document),
        # and no success line mixed into it.
        self.assertTrue(proc.stdout.endswith('</rss>\n'),
                        'trailing output after the document: %r'
                        % proc.stdout[-40:])
        items = ET.fromstring(proc.stdout).findall('./channel/item')
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].findtext(SP + 'version'), '4837')

    def test_dry_run_prints_the_full_spliced_document(self):
        before = self.write_appcast(existing_feed(existing_item('1000')))
        proc = self.publish(extra=['--dry-run'])
        self.assert_unchanged(before)
        self.assert_no_temp_files()
        self.assert_pure_insertion(
            before, proc.stdout.encode('utf-8'),
            'dry-run output is not the existing feed plus one item')
        versions = [
            item.findtext(SP + 'version')
            for item in ET.fromstring(proc.stdout).findall('./channel/item')
        ]
        self.assertEqual(versions, ['4837', '1000'])

    def test_dry_run_output_is_the_bytes_a_real_run_writes(self):
        """Section 4 step 4 has the operator approve a release by reading this
        output, so it has to be the document that then gets written. Only
        pubDate legitimately differs between the two runs."""
        before = self.write_appcast(existing_feed(existing_item('1000')))
        dry = self.publish(extra=['--dry-run']).stdout
        self.assert_unchanged(before)

        self.publish()
        real = self.read_appcast().decode('utf-8')
        self.assertEqual(mask_pub_dates(dry), mask_pub_dates(real))

    def test_dry_run_output_is_the_bytes_a_real_first_run_writes(self):
        dry = self.publish(extra=['--dry-run']).stdout
        self.assertFalse(os.path.exists(self.appcast))
        self.publish()
        real = self.read_appcast().decode('utf-8')
        self.assertEqual(mask_pub_dates(dry), mask_pub_dates(real))

    def test_dry_run_signs_for_real(self):
        self.publish(extra=['--dry-run'])
        self.assertTrue(os.path.exists(self.stdin_log))
        with open(self.stdin_log, encoding='utf-8') as f:
            self.assertEqual(f.read(), STUB_KEY)

    def test_dry_run_returns_the_exit_code_a_real_run_would(self):
        self.publish()
        before = self.read_appcast()
        proc = self.run_script(extra=['--dry-run'])
        self.assertEqual(proc.returncode, 1)
        self.assert_unchanged(before)

    def test_dry_run_catches_a_missing_sign_update(self):
        missing = os.path.join(self.tmp, 'nope', 'sign_update')
        proc = self.run_script(extra=['--dry-run'],
                               **{'--sign-update': missing})
        self.assertEqual(proc.returncode, 1)
        self.assertIn(missing, proc.stderr)


def sparkle_binary():
    matches = glob.glob(
        os.path.join(ROOT_DIR, 'Pods', 'Sparkle', 'Sparkle.framework',
                     'Versions', '*', 'Sparkle'))
    return matches[0] if matches else None


class TestSchemaNamesAgainstTheFramework(AppcastTestCase):
    """Section 2.2 -- pin the vocabulary against the Sparkle binary, not
    against our own fixture, which would pass with a wrong name.

    Sparkle's headers describe this vocabulary in prose that nothing enforces,
    and SUAppcastItem.h:167 names an attribute Sparkle does not read.
    """

    PINNED = [
        b'http://www.andymatuschak.org/xml-namespaces/sparkle',
        b'sparkle:version',
        b'sparkle:shortVersionString',
        b'sparkle:channel',
        b'sparkle:minimumSystemVersion',
        b'sparkle:edSignature',
        b'sparkle:format',
    ]

    def setUp(self):
        super().setUp()
        self.binary = sparkle_binary()
        if not self.binary:
            self.skipTest('Sparkle.framework absent; run bundle exec pod '
                          'install')
        with open(self.binary, 'rb') as f:
            self.strings = f.read()

    def test_every_emitted_name_appears_in_the_framework_binary(self):
        self.publish(**{'--channel': 'beta'})
        emitted = self.read_appcast()
        for name in self.PINNED:
            with self.subTest(name=name.decode('ascii')):
                self.assertIn(name, self.strings,
                              'not a name Sparkle reads')
                self.assertIn(name, emitted, 'name absent from our output')

    def test_description_format_attribute_is_absent_from_the_binary(self):
        self.assertNotIn(b'descriptionFormat', self.strings)

    def test_markdown_is_a_format_value_the_binary_knows(self):
        self.assertIn(b'org.sparkle-project.markdown-loader', self.strings)


if __name__ == '__main__':
    unittest.main(verbosity=2)
