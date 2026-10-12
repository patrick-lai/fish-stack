from pathlib import Path

from fishd.mlx_memory import limit_memory

# bge-small-en-v1.5 is trained with CLS pooling (1_Pooling/config.json), so vectors from
# any other pooling would not match the ones CommissionAI memory already stored.
MAX_TOKENS = 512


class EmbeddingEngine:
    def __init__(self, mx, model, tokenizer, name):
        self.mx = mx
        self.model = model
        self.tokenizer = tokenizer
        self.name = name

    def embed(self, texts):
        mx = self.mx
        encoded = self.tokenizer.batch_encode_plus(texts, return_tensors="mlx", padding=True, truncation=True, max_length=MAX_TOKENS)
        output = self.model(encoded["input_ids"], attention_mask=encoded["attention_mask"])
        cls = output.last_hidden_state[:, 0, :]
        vectors = cls / mx.sqrt(mx.sum(cls * cls, axis=-1, keepdims=True))
        tokens = int(mx.sum(encoded["attention_mask"]).item())
        mx.eval(vectors)
        return vectors.tolist(), tokens


def load_embedding_engine(model_dir: Path, name: str):
    import mlx.core as mx
    from mlx_embeddings import load

    limit_memory(mx)
    model, tokenizer = load(str(model_dir))
    return EmbeddingEngine(mx, model, tokenizer, name)
