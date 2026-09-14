#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATCHER="$ROOT/scripts/manga-zip2cbz.sh"
TEST_DEST="$(mktemp -d)"
trap 'rm -rf "$TEST_DEST"' EXIT

mkdir -p \
  "$TEST_DEST/天使が家に泊まりに来た。" \
  "$TEST_DEST/天使が家に泊まりに来た（再来）。" \
  "$TEST_DEST/お兄ちゃんの半分は欲望でできています！" \
  "$TEST_DEST/COMIC 快楽天" \
  "$TEST_DEST/COMIC 快楽天ビースト" \
  "$TEST_DEST/彼女のママもセフレにした話" \
  "$TEST_DEST/彼女の妹をセフレにした話"

assert_match() {
  local title="$1"
  local expected="$2"
  local actual
  actual="$(DEST="$TEST_DEST" "$MATCHER" --find-series "$title")"
  if [ "$actual" != "$TEST_DEST/$expected" ]; then
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
      "$title" "$TEST_DEST/$expected" "$actual" >&2
    return 1
  fi
}

assert_match "天使が家に泊まりに来た（再来）。" \
  "天使が家に泊まりに来た。"
assert_match "天使が家に泊まりに来た 後日談" \
  "天使が家に泊まりに来た。"
assert_match "お兄ちゃんの半分は欲望でできています 第4話" \
  "お兄ちゃんの半分は欲望でできています！"
assert_match "COMIC 快楽天ビースト" "COMIC 快楽天ビースト"
assert_match "彼女の妹をセフレにした話" "彼女の妹をセフレにした話"

printf 'All manga series matching tests passed.\n'
