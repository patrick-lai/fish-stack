class Refused(Exception):
    """A request the server answers with a status code and a user-safe detail.

    Pass ``code`` to answer with the pAtelier error envelope instead of ``detail`` alone.
    """

    def __init__(self, status, detail, code=None, retry_after=None):
        super().__init__(detail)
        self.status = status
        self.detail = detail
        self.code = code
        self.retry_after = retry_after
