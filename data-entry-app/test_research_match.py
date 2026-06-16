import unittest
from research_match import research_match_predicate

# Same stop-word set the endpoint passes in (mirrors SP_REFRESH_RESEARCH_RECOMMENDATIONS).
STOP = {'a', 'an', 'the', 'for', 'and', 'or', 'of', 'to', 'in', 'on', 'at',
        'by', 'is', 'it', 'my', 'with'}


class PhraseMode(unittest.TestCase):
    def test_coverage_tokenization_and_stem(self):
        # Mirrors the recommendation coverage_count: split on non-alphanumeric runs
        # (8-10 -> 8, 10), drop stop words, strip one trailing 's', space-pad each
        # token for STRPOS over the normalized candidate term.
        params, names = research_match_predicate('girls birthday gifts age 8-10', 'phrase', STOP)
        self.assertEqual(names, ['rx_0', 'rx_1', 'rx_2', 'rx_3', 'rx_4', 'rx_5'])
        self.assertEqual(params, [
            ('rx_0', ' girl '), ('rx_1', ' birthday '), ('rx_2', ' gift '),
            ('rx_3', ' age '), ('rx_4', ' 8 '), ('rx_5', ' 10 '),
        ])

    def test_singular_and_plural_seed_stem_equal(self):
        # Bidirectional plural: a plural seed token stems to the same key as its singular.
        p_sing, _ = research_match_predicate('gift', 'phrase', STOP)
        p_plur, _ = research_match_predicate('gifts', 'phrase', STOP)
        self.assertEqual(p_sing, [('rx_0', ' gift ')])
        self.assertEqual(p_plur, [('rx_0', ' gift ')])

    def test_stop_words_dropped(self):
        params, _ = research_match_predicate('gifts for the girls', 'phrase', STOP)
        self.assertEqual(params, [('rx_0', ' gift '), ('rx_1', ' girl ')])

    def test_number_token_space_padded(self):
        # ' 7 ' padded won't substring-match '17' once the candidate is space-normalized.
        params, _ = research_match_predicate('7', 'phrase', STOP)
        self.assertEqual(params, [('rx_0', ' 7 ')])

    def test_punctuation_only_token_yields_no_stems(self):
        params, names = research_match_predicate('+++', 'phrase', STOP)
        self.assertEqual((params, names), ([], []))


class DirectMode(unittest.TestCase):
    def test_full_normalized_string(self):
        params, names = research_match_predicate('girls birthday gifts age 8-10', 'direct', STOP)
        self.assertEqual(names, ['rx_0'])
        self.assertEqual(params, [('rx_0', ' girl birthday gift age 8 10 ')])

    def test_plural_collapses_to_singular(self):
        params, _ = research_match_predicate('gifts', 'direct', STOP)
        self.assertEqual(params, [('rx_0', ' gift ')])


if __name__ == '__main__':
    unittest.main()
