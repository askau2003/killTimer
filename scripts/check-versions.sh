#!/usr/bin/env bash
# Enforces this project's versioning rules: killTimer.toc's "## Version" must match
# the newest CHANGELOG.md section, and no version may be skipped. The release
# workflow turns the "## [x.y]" section matching a pushed tag into the release
# notes, so a missing or out-of-order section means a release with empty notes.
# Run it from the repository root: ./scripts/check-versions.sh

fail=0
note() { printf '%s\n' "$1" >&2; fail=1; }

toc_version=$(sed -n 's/^## Version: *//p' killTimer.toc | tr -d '\r' | head -1)
newest=$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | head -1)

if [ -z "$toc_version" ]; then
    note "killTimer.toc: no '## Version:' field"
fi
if [ -z "$newest" ]; then
    note "CHANGELOG.md: no '## [x.y]' section"
fi
if [ "$fail" -ne 0 ]; then
    exit 1
fi

if [ "$toc_version" != "$newest" ]; then
    note "killTimer.toc is version $toc_version but the newest CHANGELOG.md section is [$newest]"
fi

# Sections run newest first, so each one must be exactly one version above the
# next - except across a major bump, where x.0 follows (x-1).anything.
sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | awk '
    { version[NR] = $0 }
    END {
        for (i = 1; i < NR; i++) {
            split(version[i], newer, ".")
            split(version[i + 1], older, ".")
            ok = 0
            if (newer[1] == older[1] && newer[2] == older[2] + 1) {
                ok = 1
            } else if (newer[1] == older[1] + 1 && newer[2] == 0) {
                ok = 1
            }
            if (!ok) {
                printf "CHANGELOG.md: [%s] follows [%s] - a version is skipped or out of order\n",
                    version[i], version[i + 1] > "/dev/stderr"
                bad = 1
            }
        }
        exit bad ? 1 : 0
    }' || fail=1

if [ "$fail" -ne 0 ]; then
    exit 1
fi

printf 'versions consistent: killTimer.toc %s, CHANGELOG.md newest [%s]\n' "$toc_version" "$newest"
