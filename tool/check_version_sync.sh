#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_LINE="$(grep -E '^version: ' "$ROOT/pubspec.yaml" | head -n1)"
[[ "$VERSION_LINE" =~ ^version:\ ([0-9A-Za-z.-]+)\+([0-9]+)$ ]] || {
  echo "Versão inválida em pubspec.yaml: $VERSION_LINE" >&2
  exit 1
}
VERSION_NAME="${BASH_REMATCH[1]}"
VERSION_CODE="${BASH_REMATCH[2]}"

JSON_VERSION="$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)",$/\1/p' "$ROOT/github-manager.json" | head -n1)"
JSON_ANDROID_VERSION="$(sed -n 's/^[[:space:]]*"versionName": "\([^"]*\)",$/\1/p' "$ROOT/github-manager.json" | head -n1)"
JSON_CODE="$(sed -n 's/^[[:space:]]*"versionCode": \([0-9][0-9]*\)$/\1/p' "$ROOT/github-manager.json" | head -n1)"

test "$JSON_VERSION" = "$VERSION_NAME" || { echo "github-manager.json version=$JSON_VERSION difere de $VERSION_NAME" >&2; exit 1; }
test "$JSON_ANDROID_VERSION" = "$VERSION_NAME" || { echo "github-manager.json android.versionName=$JSON_ANDROID_VERSION difere de $VERSION_NAME" >&2; exit 1; }
test "$JSON_CODE" = "$VERSION_CODE" || { echo "github-manager.json versionCode=$JSON_CODE difere de $VERSION_CODE" >&2; exit 1; }

# Evitar alterações com versões inconsistentes em UI, documentação e release.
grep -Fq "releaseNotesVersion = '$VERSION_NAME'" "$ROOT/lib/features/update/presentation/update_whats_new_screen.dart" || {
  echo "Versão de Novidades divergente" >&2
  exit 1
}
grep -Fq "version: '$VERSION_NAME'," "$ROOT/lib/features/settings/presentation/settings_screen.dart" || {
  echo "Histórico de Configurações não inclui a versão atual" >&2
  exit 1
}
# O teste Flutter também verifica as três notas. Validar antes do analyze
# economiza minutos de Actions e sinaliza erro de documentação mais cedo.
if [[ "$VERSION_NAME" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  mapfile -t history < <(sed -nE "s/^[[:space:]]*version: '([0-9]+\.[0-9]+\.[0-9]+)',[[:space:]]*$/\1/p" \
    "$ROOT/lib/features/settings/presentation/settings_screen.dart")
  [[ "${#history[@]}" -eq 3 ]] || {
    echo "Histórico de Configurações deve ter exatamente 3 versões; encontrou ${#history[@]}" >&2
    exit 1
  }
  for offset in 0 1 2; do
    expected="$major.$minor.$((patch - offset))"
    [[ "${history[$offset]}" == "$expected" ]] || {
      echo "Histórico fora de ordem: posição $((offset + 1)) = ${history[$offset]}, esperado $expected" >&2
      exit 1
    }
  done
fi

grep -Fxq "# GitHub Manager $VERSION_NAME" "$ROOT/README.md" || {
  echo "Título do README desatualizado" >&2
  exit 1
}
grep -Fq "## $VERSION_NAME+$VERSION_CODE" "$ROOT/CHANGELOG.md" || {
  echo "CHANGELOG sem a versão atual" >&2
  exit 1
}
grep -Fq "\`version: $VERSION_NAME+$VERSION_CODE\`" "$ROOT/docs/VERSIONING.md" || {
  echo "VERSIONING sem a versão canônica" >&2
  exit 1
}
test -f "$ROOT/docs/RELEASE_$VERSION_NAME.md" || {
  echo "Notas de release da versão $VERSION_NAME ausentes" >&2
  exit 1
}

echo "versionName=$VERSION_NAME"
echo "versionCode=$VERSION_CODE"
