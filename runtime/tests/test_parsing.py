import unittest

from fishd.decision import answer, compile_request, parse_request
from fishd.errors import Refused
from fishd.hf import parse_source


class ParseSourceTests(unittest.TestCase):
    def test_repo_id_defaults_to_main(self):
        self.assertEqual(parse_source("internlm/Intern-Decision-4B"), ("internlm/Intern-Decision-4B", "main"))

    def test_model_url_keeps_the_revision_from_the_tree_path(self):
        self.assertEqual(parse_source("https://huggingface.co/internlm/Intern-Decision-4B/tree/abc123/subdir"), ("internlm/Intern-Decision-4B", "abc123"))

    def test_dataset_and_foreign_hosts_are_refused(self):
        for source in ("https://huggingface.co/datasets/owner/name", "https://example.com/owner/name", "owner/name/extra"):
            with self.subTest(source=source), self.assertRaises(Refused) as refused:
                parse_source(source)
            self.assertEqual(refused.exception.status, 422)


class DecisionRequestTests(unittest.TestCase):
    def test_a_request_without_questions_is_refused(self):
        with self.assertRaises(Refused) as refused:
            parse_request({"state": "x", "questions": {}})
        self.assertEqual(refused.exception.status, 400)

    def test_each_field_gets_one_symbol_per_option(self):
        questions = {"team": {"type": "choice", "instructions": "Which team?", "criteria": {"billing": "Payments", "shipping": "Delivery"}}}
        messages, fields, symbols = compile_request("A duplicate charge.", questions)
        self.assertEqual(fields, ["team"])
        self.assertEqual(symbols, {"team": "AB"})
        self.assertIn("A = billing: Payments", messages[1]["content"])

    def test_the_highest_scoring_choice_wins(self):
        result = answer("choice", [("billing", "Payments"), ("shipping", "Delivery")], [3.0, 0.5])
        self.assertEqual(result["choice"], "billing")
        self.assertAlmostEqual(sum(result["probabilities"].values()), 1.0, places=4)

    def test_noul_reports_the_yes_probability(self):
        result = answer("noul", [("no", "no"), ("yes", "yes")], [0.0, 0.0])
        self.assertAlmostEqual(result["noul"], 0.5, places=4)
