import unittest
from verify_official_signing import fingerprints, normalize, compare

CERT = 'ab' * 32
OTHER = 'cd' * 32


class OfficialSigningTest(unittest.TestCase):
    def test_legacy(self):
        self.assertEqual(fingerprints(f'Signer #1 certificate SHA-256 digest: {CERT}'), {CERT})

    def test_new_schemes(self):
        for scheme in ('V1', 'V2', 'V3', 'V3.0', 'V3.1', 'V3.2', 'V4'):
            with self.subTest(scheme=scheme):
                self.assertEqual(fingerprints(f'{scheme} Signer: certificate SHA-256 digest: {CERT}'), {CERT})

    def test_normalization_and_duplicate(self):
        colon = ':'.join(['AB'] * 32)
        output = f'Verifies\nV2 Signer: certificate SHA-256 digest: {colon}\nV3 Signer: certificate SHA-256 digest: {CERT}\n'
        self.assertEqual(fingerprints(output), {CERT})
        compare(fingerprints(output), CERT)
        self.assertEqual(normalize(colon), CERT)

    def test_other_digests_are_not_certificates(self):
        for line in (f'Signer #1 public key SHA-256 digest: {CERT}', f'Source Stamp Signer certificate SHA-256 digest: {CERT}', 'Verifies'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                fingerprints(line)

    def test_wrong_certificate_rejected(self):
        with self.assertRaises(ValueError):
            compare({OTHER}, CERT)
        with self.assertRaises(ValueError):
            compare({CERT, OTHER}, CERT)

    def test_malformed_certificate_rejected(self):
        with self.assertRaises(ValueError):
            fingerprints('V2 Signer: certificate SHA-256 digest: 123')


if __name__ == '__main__':
    unittest.main()
