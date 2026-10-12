import json
import math
from pathlib import Path

from fishd.errors import Refused
from fishd.mlx_memory import limit_memory

# Ported from jev-local so CommissionAI's decision requests get the same answers.
DECISION_TOKEN = "<decision>"
ANSWER_SYMBOLS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
# The temperature was fitted to the model's logits; changing it shifts every probability.
TEMPERATURE = 1.99241824
MAX_QUESTIONS = 64
MAX_STATE_CHARS = 50000
MAX_PROMPT_TOKENS = 8192
SYSTEM_PROMPT = "You are a careful decision assistant. Use the state and decision schema in the user message to make the requested decisions. For every field, choose exactly one answer symbol (e.g. A, B, C, ...) from its listed options and return one valid JSON object mapping each field name to its chosen symbol. Use the field names and symbols exactly as given. Do not include explanations, Markdown, or extra text."


def parse_request(body):
    if not isinstance(body, dict) or not isinstance(body.get("questions"), dict) or not body["questions"]:
        raise Refused(400, "request body must be an object with a 'questions' object")
    questions = body["questions"]
    if len(questions) > MAX_QUESTIONS:
        raise Refused(413, "too many questions (%d > %d)" % (len(questions), MAX_QUESTIONS))
    state = body.get("state")
    if len(state if isinstance(state, str) else json.dumps(state)) > MAX_STATE_CHARS:
        raise Refused(413, "state too large")
    return state, questions


def options(question):
    kind = question.get("type")
    criteria = question.get("criteria")
    if kind == "choice":
        if not isinstance(criteria, dict) or not criteria:
            raise Refused(422, "choice criteria must be a non-empty object")
        return [(str(key), str(value)) for key, value in criteria.items()]
    if kind == "score":
        if isinstance(criteria, list) and criteria:
            return [(str(index), str(value)) for index, value in enumerate(criteria)]
        raise Refused(422, "score criteria must be a non-empty list")
    if kind == "noul":
        return [("no", "The answer is no (negative, or disagree with the claim)."), ("yes", "The answer is yes (affirmative, or align with the claim).")]
    raise Refused(422, "question type must be noul, choice or score")


def compile_request(state, questions):
    fields, symbols, lines = [], {}, []
    for field, question in questions.items():
        if not isinstance(question, dict):
            raise Refused(422, "question %s is not an object" % field)
        choices = options(question)
        if len(choices) > len(ANSWER_SYMBOLS):
            raise Refused(422, "at most %d options per question" % len(ANSWER_SYMBOLS))
        fields.append(str(field))
        symbols[str(field)] = ANSWER_SYMBOLS[: len(choices)]
        lines.append("%s: %s" % (field, question.get("instructions", "")))
        for symbol, (value, description) in zip(symbols[str(field)], choices):
            lines.append("    %s = %s: %s" % (symbol, value, description))
    text = "Return one answer for every field using the supplied answer symbols.\n\n## State\n%s\n## Decision schema\n%s" % (json.dumps(state, ensure_ascii=False, indent=2), "\n".join(lines))
    if DECISION_TOKEN in text:
        raise Refused(422, "the reserved decision marker appears in the input")
    # The assistant turn is a skeleton of markers. Each marker's logits are read for one field.
    skeleton = json.dumps(dict.fromkeys(fields, DECISION_TOKEN), ensure_ascii=False, indent=4)
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": text}, {"role": "assistant", "content": skeleton}]
    return messages, fields, symbols


def answer(kind, choices, scores):
    top = max(scores)
    weights = [math.exp((value - top) / TEMPERATURE) for value in scores]
    total = sum(weights)
    names = [value for value, _ in choices]
    probabilities = {name: round(weight / total, 6) for name, weight in zip(names, weights)}
    best = min(names, key=lambda name: (-probabilities[name], name))
    if kind == "noul":
        return {"type": "noul", "noul": round(probabilities["yes"], 4)}
    if kind == "score":
        return {"type": "score", "score": round(sum(float(name) * probabilities[name] for name in names), 4), "confidence": round(probabilities[best], 4), "probabilities": probabilities}
    return {"type": "choice", "choice": best, "confidence": round(probabilities[best], 4), "probabilities": probabilities}


class DecisionEngine:
    def __init__(self, mx, tokenizer, language, name, max_prompt_tokens=MAX_PROMPT_TOKENS):
        self.mx = mx
        self.tokenizer = tokenizer
        self.language = language
        self.name = name
        self.max_prompt_tokens = max_prompt_tokens
        self.marker = tokenizer.convert_tokens_to_ids(DECISION_TOKEN)

    def decide(self, state, questions):
        messages, fields, symbols = compile_request(state, questions)
        text = self.tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=False, enable_thinking=False, add_vision_id=True)
        ids = self.tokenizer(text, add_special_tokens=False)["input_ids"]
        if len(ids) > self.max_prompt_tokens:
            raise Refused(413, "local model input is too long (%d > %d tokens); shorten state, question instructions or criteria" % (len(ids), self.max_prompt_tokens))
        positions = [index - 1 for index, token in enumerate(ids) if token == self.marker]
        if len(positions) != len(fields) or any(position < 0 for position in positions):
            raise Refused(422, "decision marker count does not match the questions")
        mx = self.mx
        body = self.language.model
        hidden = body(mx.array(ids)[None])[0]
        rows = hidden[mx.array(positions)]
        logits = self.language.lm_head(rows) if hasattr(self.language, "lm_head") else body.embed_tokens.as_linear(rows)
        mx.eval(logits)
        answers = {}
        for index, field in enumerate(fields):
            question = questions[field]
            picks = mx.array([self.tokenizer.encode(symbol, add_special_tokens=False)[0] for symbol in symbols[field]])
            scores = [float(value) for value in logits[index][picks].astype(mx.float32).tolist()]
            answers[field] = answer(question["type"], options(question), scores)
        return {"model": self.name, "answers": answers, "usage": {"input_tokens": len(ids), "output_tokens": 0}}


def load_decision_engine(model_dir: Path, name: str):
    import mlx.core as mx
    from mlx_lm.utils import load_model
    from transformers import AutoTokenizer

    limit_memory(mx)
    tokenizer = AutoTokenizer.from_pretrained(str(model_dir), local_files_only=True)
    model, _ = load_model(model_dir)
    language = getattr(model, "language_model", model)
    return DecisionEngine(mx, tokenizer, language, name)
