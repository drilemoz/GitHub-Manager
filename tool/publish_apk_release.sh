#!/usr/bin/env bash
set -euo pipefail
APK="${1:?Informe o APK oficial}"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n1)"
NAME="${VERSION%%+*}"
CODE="${VERSION##*+}"
TAG="v$NAME"
FILE="GitHub-Manager-$NAME-$CODE-universal-release.apk"
test "$(basename "$APK")" = "$FILE"
test -s "$APK"
# Nunca substitua APK oficial publicado para a mesma versão.
if gh release view "$TAG" --json isDraft,assets > /tmp/ghm-release.json 2>/dev/null; then
  if jq -e --arg name "$FILE" '.isDraft == false and any(.assets[]; .name == $name and .size > 0)' /tmp/ghm-release.json >/dev/null; then
    echo "Release $TAG já publicada com APK oficial; preservada."
    exit 0
  fi
  if ! jq -e '.isDraft == true' /tmp/ghm-release.json >/dev/null; then
    # Permite completar uma release antiga sem APK, sem sobrescrever outros assets.
    gh release upload "$TAG" "$APK"
    exit 0
  fi
else
  gh release create "$TAG" --target "$GITHUB_SHA" --draft --title "GitHub Manager $NAME" --notes-file "docs/RELEASE_$NAME.md"
fi
# Só publica depois do upload. Se uma execução anterior deixou o rascunho,
# retoma sem deixar uma release pública vazia.
gh release upload "$TAG" "$APK" --clobber
gh release edit "$TAG" --draft=false --prerelease=false --latest
