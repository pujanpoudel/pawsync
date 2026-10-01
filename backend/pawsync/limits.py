import hashlib
import time

from redis import Redis
from redis.exceptions import RedisError

from .wallet import WalletError


class RateLimiter:
    """Atomic Redis window shared by all API workers. Fails closed when Redis is down."""
    script = """
    local n = redis.call('INCR', KEYS[1])
    if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
    return n
    """

    def __init__(self, url):
        self.redis = Redis.from_url(url, socket_connect_timeout=2, socket_timeout=2)

    def check(self, scope, identity, ceiling, period=60):
        fingerprint = hashlib.sha256(identity.encode()).hexdigest()
        key = f"pawsync:rate:{scope}:{fingerprint}:{int(time.time()) // period}"
        try:
            count = self.redis.eval(self.script, 1, key, period + 1)
        except RedisError:
            raise WalletError("Rate-limit service unavailable", 503) from None
        if count > ceiling:
            raise WalletError("Too many requests. Please wait and retry.", 429)
