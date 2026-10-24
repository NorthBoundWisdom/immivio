"""Structured FreeCM exception types."""

from __future__ import annotations


class FreeCMError(Exception):
    """Base class for FreeCM domain errors."""


class LockfileValidationError(FreeCMError, ValueError):
    """A lock, policy, or JSONC document failed schema validation."""


class RepoCommandManifestError(FreeCMError, ValueError):
    """A repository command manifest failed structural validation."""


class SeedRepositoryError(FreeCMError, RuntimeError):
    """A dependency seed repository is missing, dirty, or otherwise unusable."""


class MaterializationError(FreeCMError, RuntimeError):
    """Dependency materialization failed after resolution."""
