class Refused(Exception):
    """A request the server answers with a status code and a user-safe detail."""

    def __init__(self, status, detail):
        super().__init__(detail)
        self.status = status
        self.detail = detail
