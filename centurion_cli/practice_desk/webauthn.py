"""Backwards-compatible import shim.

Passkey verification was lifted out of the practice desk at Gate 1 of the
interface programme so that identity belongs to the Brain rather than to one
product. The code now lives in :mod:`centurion_identity.webauthn`; this module
is the same object under the old name, so nothing that imports it breaks and
the two can never drift.
"""

import sys

from centurion_identity import webauthn as _webauthn

sys.modules[__name__] = _webauthn
