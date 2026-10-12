ROLES = ("decision", "embedding")

DEFAULT_CONFIG = {
    "download_on_start": True,
    "decision": {"repo": "internlm/Intern-Decision-4B", "revision": "0e5e6aa7d6d750e2b1504ba11a8136cb58aeb3cd"},
    "embedding": {"repo": "mlx-community/bge-small-en-v1.5-4bit", "revision": "6d66cdf333ff5d4cdad084f2fc2a619575d064ab"},
}

# The decision model is multimodal; only the language tower is needed for text decisions.
ROLE_PATTERNS = {
    "decision": [
        "model-language-*.safetensors",
        "model.safetensors.index.json",
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "added_tokens.json",
        "special_tokens_map.json",
        "vocab.json",
        "merges.txt",
        "chat_template.jinja",
        "generation_config.json",
    ],
    "embedding": ["*.safetensors", "*.json", "*.txt"],
}

CONVERT_SUPPORT_FILES = ["added_tokens.json", "special_tokens_map.json", "vocab.json", "merges.txt"]
