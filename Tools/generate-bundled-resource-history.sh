#!/bin/bash
#
#  generate-bundled-resource-history.sh
#  MacDown 3000
#
#  Regenerates MacDown/Resources/BundledResourceHistory.json: for every file
#  under MacDown/Resources/Styles and MacDown/Resources/Themes, the set of
#  SHA-256 digests that file has ever had at a shipped release tag.
#
#  MPBundledResourceSync reads that manifest at launch to tell "this is an
#  older bundled version, refresh it" apart from "the user edited this, leave
#  it alone forever". A wrong digest in here destroys a user's file, so this
#  script fails loudly rather than emit anything it cannot justify.
#
#  Usage:
#      Tools/generate-bundled-resource-history.sh           # regenerate
#      Tools/generate-bundled-resource-history.sh --check   # verify only
#
#  --check regenerates into a temporary file and diffs it against the
#  committed one, exiting non-zero on drift. The generator is deterministic:
#  re-running it against an unchanged tag set produces byte-identical output
#  (there is deliberately no timestamp field anywhere in the manifest), so
#  --check is meaningful and cheap enough to wire into CI.
#
#  This script is NOT part of the Xcode build. It is run by hand when a new
#  release tag is cut, and the resulting JSON is committed.
#
#  Related to GitHub issue #548.
#
# ---------------------------------------------------------------------------
#  Why hashing checked-out bytes is sound
# ---------------------------------------------------------------------------
#
#  We digest the bytes committed at each tag, and claim those are the bytes
#  that shipped inside the .app. That claim only holds if no build step ever
#  regenerated one of these files on the release machine.
#
#  There is exactly one such step: the "Transpile Styles" build phase runs
#  `make -C Tools/GitHub-style-generator/`, which regenerates
#  MacDown/Resources/Styles/GitHub-2020.css from index.sass. That Makefile
#  invokes `node_modules/.bin/sass` -- i.e. it cannot run at all unless an
#  npm/yarn install has populated node_modules. The release pipeline has never
#  had node, npm or yarn available:
#
#    * .github/actions/setup-macdown/action.yml has had exactly one version,
#      commit e96c19f ("Refactor release automation and documentation", #154).
#      It has three steps: ruby/setup-ruby@v1, `bundle exec pod install`, and
#      `make -C Dependency/peg-markdown-highlight`. No node, ever.
#    * .github/workflows/release.yml and its pre-refactor ancestor 0dcd4dd
#      ("Add code signing and release automation to CI/CD", #69) have the same
#      empty footprint across their whole history.
#
#  So `make` finds node_modules/.bin/sass missing, the recipe fails, and the
#  committed GitHub-2020.css ships verbatim. check_no_node() below re-verifies
#  this every time the generator runs; if it ever stops holding, the generator
#  refuses to emit and you must fall back to downloading the released .app
#  artifacts and diffing their Resources against these digests.
#
# ---------------------------------------------------------------------------

set -euo pipefail

fatal()
{
    echo >&2 "FATAL: $*"
    exit 1
}

CHECK_ONLY=0
case "${1-}" in
    --check)    CHECK_ONLY=1 ;;
    -h|--help)  sed -n '3,26p' "$0"; exit 0 ;;
    "")         ;;
    *)          fatal "unknown argument '$1' (expected --check or nothing)" ;;
esac


# --- Step 1: preflight -----------------------------------------------------
# Same `hash <tool> || { echo >&2 …; exit; }` idiom as Tools/utils.sh:1.
# python3 is not a new dependency: Tools/compat.py and Tools/macdown_utils.py
# already require it.

hash git 2>/dev/null || \
    { echo >&2 "Git required, not installed.  Aborting history generation."; exit 1; }
hash shasum 2>/dev/null || \
    { echo >&2 "shasum required, not installed.  Aborting history generation."; exit 1; }
hash python3 2>/dev/null || \
    { echo >&2 "python3 required, not installed.  Aborting history generation."; exit 1; }

# Run from the repository root, using the `pushd $(dirname $0)` pattern from
# Tools/generate_version_header.sh:3-5.
pushd "$(dirname "$0")/.." > /dev/null
REPO_ROOT="$(pwd -P)"
popd > /dev/null
cd "$REPO_ROOT"

readonly RESOURCE_PREFIX="MacDown/Resources/"
readonly OUTPUT_PATH="MacDown/Resources/BundledResourceHistory.json"
readonly RESOURCE_DIRS=(
    "MacDown/Resources/Styles"
    "MacDown/Resources/Themes"
)

TMPDIR_WORK="$(mktemp -d "${TMPDIR:-/tmp}/bundled-resource-history.XXXXXX")"
trap 'rm -rf "$TMPDIR_WORK"' EXIT


# --- Step 2: ensure full history -------------------------------------------
# A CI checkout or a fresh clone may be shallow and tagless, which would
# silently produce an empty manifest.

# Retries a network command up to 4 times with 2s/4s/8s/16s backoff.
retry_network()
{
    local delay=2 attempt
    for attempt in 1 2 3 4 5; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -eq 5 ]; then
            return 1
        fi
        echo >&2 "warning: '$*' failed; retrying in ${delay}s"
        sleep "$delay"
        delay=$(( delay * 2 ))
    done
}

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    retry_network git fetch --unshallow --tags || \
        fatal "repository is shallow and could not be unshallowed; the tag history needed to build this manifest is unavailable."
else
    retry_network git fetch --tags || \
        echo >&2 "warning: could not fetch tags; using local tags"
fi


# --- Step 3: the static no-node check, before any digesting ----------------
#
# Pattern note (deliberate narrowing from the original draft): the draft
# pattern was
#     npm|nodejs|node-version|setup-node|yarn|sass
# `sass` has been REPLACED by `npx` and `node_modules`. Reasoning:
#
#   * `sass` adds no detection power. The only thing that could invalidate
#     these digests is the Transpile Styles phase actually succeeding, and its
#     Makefile hardcodes `node_modules/.bin/sass` -- reachable only via an
#     npm/yarn install, which the remaining terms already catch. A
#     brew/gem-installed dart-sass would not satisfy that path.
#   * `sass` is the term most likely to appear innocuously: this repo really
#     does contain Tools/GitHub-style-generator/index.sass, so a `paths:`
#     filter, a step name, or a comment mentioning it in either file would
#     trip the check permanently, with no way to clear it short of editing
#     this script. A permanent false positive on a check whose only action is
#     `exit 1` is worse than no check.
#   * `npx` and `node_modules` are the capability markers actually missing
#     from the draft, so the narrowed pattern strictly increases the chance of
#     catching a genuine node/npm capability landing in the release pipeline.
#
# Both files currently produce zero hits under either pattern (verified).

check_no_node()
{
    local path="$1"
    local hits
    hits=$(git log --all --oneline -p -- "$path" \
           | grep -inE '^\+.*(npm|npx|node_modules|nodejs|node-version|setup-node|yarn)' || true)
    if [ -n "$hits" ]; then
        echo >&2 "FATAL: node/npm footprint found in $path:"
        echo >&2 "$hits"
        echo >&2 "The 'no node in the release pipeline' assumption no longer"
        echo >&2 "holds, so checked-out bytes may not be the bytes that"
        echo >&2 "shipped. Fall back to the artifact download-and-diff"
        echo >&2 "verification before trusting these digests. Refusing to emit."
        exit 1
    fi
}

check_no_node .github/actions/setup-macdown/action.yml
check_no_node .github/workflows/release.yml


# --- Step 4: enumerate tags ------------------------------------------------
# -beta.* and -rc.* tags are included on purpose: those were downloadable
# releases, users ran them, and their bytes are legitimately on disk
# somewhere. versionsort.suffix=- sorts a prerelease before its release
# (v3000.0.7-rc.3 before v3000.0.7) instead of lexicographically after it.

git -c versionsort.suffix=- tag --list 'v*' --sort=v:refname > "$TMPDIR_WORK/tags.txt"

TAG_COUNT="$(grep -c . "$TMPDIR_WORK/tags.txt" || true)"
if [ "$TAG_COUNT" -eq 0 ]; then
    fatal "no 'v*' tags found. Emitting an empty history manifest would let every user file classify as unknown and never be refreshed; refusing to emit."
fi


# --- Step 5: enumerate and digest files at each tag ------------------------
#
# Four things here are load-bearing:
#
#   * `-z` plus `read -r -d ''` are mandatory, not stylistic. 19 of the 28
#     filenames contain spaces or parentheses -- "Solarized (Dark).style",
#     "Mou Night+.style", "Google Docs.css". Word-splitting `git ls-tree
#     --name-only` output shreds them into fragments and either errors out or,
#     worse, silently digests the wrong blob.
#   * `git ls-tree -r` without `-t` lists blobs only, so trees never appear.
#     The mode filter is still needed to skip symlinks (120000) and gitlinks
#     (160000): the runtime never follows or hashes a non-regular file, so
#     shipping a digest for one would be meaningless.
#   * ENUMERATE, NEVER PROBE. Files that did not exist at a tag simply are not
#     listed, and need no handling at all. `git show "$tag:$path"` against a
#     hardcoded filename list is the anti-pattern: it produces "fatal: path …
#     does not exist" and a non-zero exit under `set -e`. 22 files exist at
#     v3000.0.0-beta.0 and 28 at v3000.0.7; enumeration absorbs the difference
#     with zero special-casing.
#   * `shasum -a 256` emits lowercase hex, matching CommonCrypto's "%02x" on
#     the Objective-C side. The runtime compares digests case-sensitively.
#
# Step 6 -- filename changes. Keys are the path as spelled AT EACH TAG, so a
# rename would produce two independent keys. That is correct and needs no
# rename detection: the user has the old filename on disk, it is absent from
# the current bundle, so the sync's row-7 rule leaves it alone forever, while
# the new filename is covered by its own key. Content-matching heuristics
# would only create ways to overwrite a file we cannot justify overwriting.
# Verified, and worth re-running before assuming otherwise:
#
#     git log --diff-filter=R --name-status -- \
#         'MacDown/Resources/Styles/*' 'MacDown/Resources/Themes/*'
#
# is empty -- this repo has never renamed one of these files.

emit_pairs_for_ref()
{
    local ref="$1"
    local dir entry mode path key digest

    for dir in "${RESOURCE_DIRS[@]}"; do
        git ls-tree -r -z "$ref" -- "$dir" > "$TMPDIR_WORK/ls-tree.bin"
        while IFS= read -r -d '' entry; do
            # "<mode> SP <type> SP <object> TAB <path>"
            mode="${entry%% *}"
            path="${entry#*$'\t'}"
            case "$mode" in
                100644|100755) ;;
                *) continue ;;
            esac
            key="${path#"$RESOURCE_PREFIX"}"
            digest="$(git cat-file blob "$ref:$path" | shasum -a 256 | cut -d' ' -f1)"
            printf '%s\t%s\n' "$key" "$digest"
        done < "$TMPDIR_WORK/ls-tree.bin"
    done
}

count_regular_files_at_ref()
{
    local ref="$1"
    local dir entry mode count=0

    for dir in "${RESOURCE_DIRS[@]}"; do
        git ls-tree -r -z "$ref" -- "$dir" > "$TMPDIR_WORK/ls-count.bin"
        while IFS= read -r -d '' entry; do
            mode="${entry%% *}"
            case "$mode" in
                100644|100755) count=$(( count + 1 )) ;;
            esac
        done < "$TMPDIR_WORK/ls-count.bin"
    done
    printf '%s\n' "$count"
}

{
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        emit_pairs_for_ref "$tag"
    done < "$TMPDIR_WORK/tags.txt"
} | LC_ALL=C sort -u > "$TMPDIR_WORK/pairs.tsv"


# --- Step 8 (first half): self-checks on the raw pairs ---------------------
# Run before emission so a malformed pair never reaches the output file.

if [ ! -s "$TMPDIR_WORK/pairs.tsv" ]; then
    fatal "enumerated $TAG_COUNT tag(s) but produced zero (path, digest) pairs."
fi

MALFORMED="$(LC_ALL=C grep -cvE $'^[^\t]+\t[^\t]+$' "$TMPDIR_WORK/pairs.tsv" || true)"
if [ "$MALFORMED" -ne 0 ]; then
    fatal "$MALFORMED line(s) of the pair stream are not exactly two tab-separated fields."
fi

BAD_DIGESTS="$(LC_ALL=C cut -f2 "$TMPDIR_WORK/pairs.tsv" \
               | LC_ALL=C grep -vE '^[0-9a-f]{64}$' | sort -u || true)"
if [ -n "$BAD_DIGESTS" ]; then
    echo >&2 "$BAD_DIGESTS"
    fatal "digest(s) above do not match ^[0-9a-f]{64}\$."
fi

BAD_KEYS="$(LC_ALL=C cut -f1 "$TMPDIR_WORK/pairs.tsv" \
            | LC_ALL=C grep -vE '^(Styles|Themes)/[^/]+$' | sort -u || true)"
if [ -n "$BAD_KEYS" ]; then
    echo >&2 "$BAD_KEYS"
    fatal "key(s) above do not match ^(Styles|Themes)/[^/]+\$."
fi

KEY_COUNT="$(LC_ALL=C cut -f1 "$TMPDIR_WORK/pairs.tsv" | LC_ALL=C sort -u | wc -l | tr -d ' ')"
PAIR_COUNT="$(wc -l < "$TMPDIR_WORK/pairs.tsv" | tr -d ' ')"
CURRENT_COUNT="$(count_regular_files_at_ref HEAD)"

if [ "$KEY_COUNT" -lt "$CURRENT_COUNT" ]; then
    fatal "enumeration produced $KEY_COUNT key(s) but HEAD ships $CURRENT_COUNT file(s); files were silently lost."
fi


# --- Step 7: deterministic emission ----------------------------------------
# LC_ALL=C sort above and Python's sort_keys=True are both byte/codepoint
# order, so the two agree. indent=2, ensure_ascii=False, trailing newline,
# sorted and de-duplicated digest arrays, and NO timestamp -- a timestamp
# would make the generator non-idempotent and turn every regeneration into an
# unreviewable diff.

LC_ALL=C python3 - "$TMPDIR_WORK/pairs.tsv" "$TMPDIR_WORK/tags.txt" \
    > "$TMPDIR_WORK/BundledResourceHistory.json" <<'PY'
import collections
import json
import re
import sys

DIGEST_RE = re.compile(r'^[0-9a-f]{64}$')
KEY_RE = re.compile(r'^(Styles|Themes)/[^/]+$')

files = collections.defaultdict(set)
with open(sys.argv[1], encoding='utf-8') as handle:
    for line in handle:
        line = line.rstrip('\n')
        if not line:
            continue
        key, _, digest = line.partition('\t')
        assert KEY_RE.match(key), 'bad key: %r' % (key,)
        assert DIGEST_RE.match(digest), 'bad digest for %r: %r' % (key, digest)
        files[key].add(digest)

with open(sys.argv[2], encoding='utf-8') as handle:
    tags = [t.strip() for t in handle if t.strip()]
assert tags, 'empty tag list'

doc = {
    "version": 1,
    "tags": tags,
    "files": {key: sorted(values) for key, values in files.items()},
}
json.dump(doc, sys.stdout, indent=2, sort_keys=True, ensure_ascii=False)
sys.stdout.write("\n")
PY


# --- Step 8 (second half): self-checks on the emitted document -------------

LC_ALL=C python3 - "$TMPDIR_WORK/BundledResourceHistory.json" "$CURRENT_COUNT" <<'PY'
import json
import re
import sys

DIGEST_RE = re.compile(r'^[0-9a-f]{64}$')
KEY_RE = re.compile(r'^(Styles|Themes)/[^/]+$')

with open(sys.argv[1], encoding='utf-8') as handle:
    doc = json.load(handle)

assert doc["version"] == 1, doc["version"]
assert isinstance(doc["tags"], list) and doc["tags"], "tags"
assert "timestamp" not in doc, "a timestamp field would break idempotence"

files = doc["files"]
for key, digests in files.items():
    assert KEY_RE.match(key), 'bad key: %r' % (key,)
    assert digests, 'empty digest array for %r' % (key,)
    assert digests == sorted(set(digests)), 'unsorted/duplicated digests for %r' % (key,)
    for digest in digests:
        assert DIGEST_RE.match(digest), 'bad digest for %r: %r' % (key, digest)

current = int(sys.argv[2])
assert len(files) >= current, \
    'only %d key(s) for %d shipped file(s)' % (len(files), current)
PY


# --- Step 9: --check mode, or write ----------------------------------------

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ ! -f "$OUTPUT_PATH" ]; then
        fatal "$OUTPUT_PATH does not exist. Run this script without --check."
    fi
    if ! diff -u "$OUTPUT_PATH" "$TMPDIR_WORK/BundledResourceHistory.json"; then
        fatal "$OUTPUT_PATH is out of date. Run Tools/generate-bundled-resource-history.sh."
    fi
    echo "$OUTPUT_PATH is up to date ($KEY_COUNT keys, $PAIR_COUNT digests, $TAG_COUNT tags)."
    exit 0
fi

cat "$TMPDIR_WORK/BundledResourceHistory.json" > "$OUTPUT_PATH"

BYTE_COUNT="$(wc -c < "$OUTPUT_PATH" | tr -d ' ')"
echo "Wrote $OUTPUT_PATH: $KEY_COUNT keys, $PAIR_COUNT distinct (path, digest) pairs, $TAG_COUNT tags, $BYTE_COUNT bytes."
