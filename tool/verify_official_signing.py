#!/usr/bin/env python3
"""Check the pinned official certificate, independently of apksigner output format."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

SIGNER = re.compile(
    r'^\s*(?:V\d+(?:\.\d+)?\s+)?Signer(?:\s+#\d+)?\s*:?\s+certificate\s+SHA-256\s+digest:\s*(.*?)\s*$',
    re.IGNORECASE,
)


def normalize(value):
    value = value.replace(':', '').strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', value):
        raise ValueError('SHA-256 ausente ou inválido.')
    return value


def fingerprints(output):
    values = {normalize(m.group(1)) for line in output.splitlines()
              if (m := SIGNER.fullmatch(line))}
    if not values:
        raise ValueError('Nenhum SHA-256 de certificado de assinante reconhecido na saída do apksigner.')
    return values


def compare(actual, expected):
    if actual != {expected}:
        raise ValueError(f'Certificado oficial divergente. Esperado: {expected}; encontrado(s): {", ".join(sorted(actual))}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--properties', type=Path, default=Path('android/release-signing.properties'))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--apk', type=Path)
    mode.add_argument('--keystore', type=Path)
    parser.add_argument('--apksigner')
    args = parser.parse_args()
    try:
        expected = normalize(next(line.split('=', 1)[1] for line in args.properties.read_text().splitlines()
                                  if line.startswith('certificateSha256=')))
        if args.apk:
            if not args.apksigner:
                raise ValueError('Informe --apksigner para validar o APK.')
            result = subprocess.run([args.apksigner, 'verify', '--print-certs', str(args.apk)],
                                    capture_output=True, text=True, check=False)
            # Output contains public certificate information only. Keep it for diagnostics.
            if result.stdout:
                print(result.stdout, end='')
            if result.stderr:
                print(result.stderr, end='', file=sys.stderr)
            if result.returncode:
                raise ValueError(f'apksigner não validou o APK (exit {result.returncode}).')
            actual = fingerprints(result.stdout)
        else:
            # Password passed by environment, not command line; hash the public DER certificate.
            result = subprocess.run(['keytool', '-exportcert', '-keystore', str(args.keystore),
                                     '-alias', os.environ['KEY_ALIAS'], '-storepass:env', 'KEYSTORE_PASSWORD'],
                                    capture_output=True, check=False)
            if result.returncode or not result.stdout:
                raise ValueError('Não foi possível exportar o certificado da keystore oficial. Confira alias e senha nos Secrets.')
            actual = {hashlib.sha256(result.stdout).hexdigest()}
        compare(actual, expected)
        print(f'Certificado oficial confirmado: {expected}')
    except (ValueError, OSError, KeyError, StopIteration) as exc:
        print(f'::error::Falha na validação da assinatura: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
