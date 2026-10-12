MEMORY_LIMIT_BYTES = 8192 << 20
CACHE_LIMIT_BYTES = 256 << 20


def limit_memory(mx):
    # Caps MLX's allocator so a runaway request cannot take the whole Mac's unified memory.
    mx.set_memory_limit(MEMORY_LIMIT_BYTES)
    mx.set_cache_limit(CACHE_LIMIT_BYTES)
