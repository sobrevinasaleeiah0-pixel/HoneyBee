"""Canonical class definitions for Honeybee Center 9-Class Object Detection.

Provides immutable mappings, bidirectional lookups, alias resolution,
and count-map initialization for the 9 distinct commercial honey bottle classes:

    0: 200g
    1: 250g
    2: 350g
    3: 400g
    4: 500g
    5: 650g
    6: 660g
    7: 1000g (1kg)
    8: 1350g

IMPORTANT:
    - 650g (Wild Honey) and 660g (Cultured Honey) are separate SKUs. NEVER merge them.
    - 1000g represents 1kg. "1kg" is an authorized alias mapping to "1000g" (ID 7).
"""

from types import MappingProxyType
from typing import Dict, Mapping, Tuple


class DetectorClassError(ValueError):
    """Base exception for detector class lookup and validation errors."""
    pass


class InvalidClassIdError(DetectorClassError):
    """Raised when a class ID is not within the canonical [0..8] range."""
    pass


class InvalidClassNameError(DetectorClassError):
    """Raised when a class name/label is not a recognized canonical class or alias."""
    pass


# Canonical mapping: ID (int) -> Canonical Label (str)
_CANONICAL_ID_TO_CLASS: Dict[int, str] = {
    0: "200g",
    1: "250g",
    2: "350g",
    3: "400g",
    4: "500g",
    5: "650g",
    6: "660g",
    7: "1000g",
    8: "1350g",
}

# Inverted mapping: Canonical Label (str) -> ID (int)
_CANONICAL_CLASS_TO_ID: Dict[str, int] = {
    name: class_id for class_id, name in _CANONICAL_ID_TO_CLASS.items()
}

# Alias resolution mapping: alias (lowercase, stripped) -> Canonical Label (str)
_CLASS_ALIASES: Dict[str, str] = {
    "1kg": "1000g",
    "1 kg": "1000g",
    "1.0kg": "1000g",
    "1000g": "1000g",
}

# Immutable views protecting internal mappings from accidental external mutation
CANONICAL_CLASSES: Mapping[int, str] = MappingProxyType(_CANONICAL_ID_TO_CLASS)
CANONICAL_CLASS_NAMES: Mapping[str, int] = MappingProxyType(_CANONICAL_CLASS_TO_ID)
CLASS_ALIASES: Mapping[str, str] = MappingProxyType(_CLASS_ALIASES)


def get_canonical_classes() -> Mapping[int, str]:
    """Return an immutable mapping of all canonical class IDs to class names."""
    return CANONICAL_CLASSES


def get_all_class_ids() -> Tuple[int, ...]:
    """Return a tuple of all canonical class IDs in ascending order (0..8)."""
    return tuple(sorted(_CANONICAL_ID_TO_CLASS.keys()))


def get_all_class_names() -> Tuple[str, ...]:
    """Return a tuple of all canonical class names ordered by class ID."""
    return tuple(_CANONICAL_ID_TO_CLASS[i] for i in sorted(_CANONICAL_ID_TO_CLASS.keys()))


def normalize_class_name(class_name: str) -> str:
    """Normalize a class name, resolving aliases (e.g., '1kg' -> '1000g').

    Args:
        class_name: Name or alias of the bottle class.

    Returns:
        Canonical class label string.

    Raises:
        InvalidClassNameError: If the name/alias is not recognized.
    """
    if not isinstance(class_name, str):
        raise InvalidClassNameError(
            f"Class name must be a string, got {type(class_name).__name__}: {class_name!r}"
        )

    cleaned = class_name.strip().lower()

    # Check direct canonical match (case-insensitive)
    for canonical_name in _CANONICAL_CLASS_TO_ID:
        if cleaned == canonical_name.lower():
            return canonical_name

    # Check alias match
    if cleaned in _CLASS_ALIASES:
        return _CLASS_ALIASES[cleaned]

    valid_options = list(_CANONICAL_CLASS_TO_ID.keys()) + list(_CLASS_ALIASES.keys())
    raise InvalidClassNameError(
        f"Unknown class name {class_name!r}. Must be one of canonical classes {list(_CANONICAL_CLASS_TO_ID.keys())} "
        f"or aliases {list(_CLASS_ALIASES.keys())}."
    )


def id_to_class(class_id: int) -> str:
    """Lookup the canonical class name for a given class ID.

    Args:
        class_id: Integer ID in range [0..8].

    Returns:
        Canonical class name string.

    Raises:
        InvalidClassIdError: If class_id is not an integer in [0..8].
    """
    if not isinstance(class_id, int) or isinstance(class_id, bool):
        raise InvalidClassIdError(
            f"Class ID must be an integer, got {type(class_id).__name__}: {class_id!r}"
        )

    if class_id not in _CANONICAL_ID_TO_CLASS:
        raise InvalidClassIdError(
            f"Invalid class ID {class_id}. Allowed IDs are {list(_CANONICAL_ID_TO_CLASS.keys())}."
        )

    return _CANONICAL_ID_TO_CLASS[class_id]


def class_to_id(class_name: str) -> int:
    """Lookup the canonical class ID for a given class name or alias.

    Args:
        class_name: Canonical class label or authorized alias (e.g. '250g', '1kg').

    Returns:
        Canonical integer class ID (0..8).

    Raises:
        InvalidClassNameError: If class_name cannot be resolved.
    """
    canonical_name = normalize_class_name(class_name)
    return _CANONICAL_CLASS_TO_ID[canonical_name]


def is_valid_class_id(class_id: int) -> bool:
    """Check whether a class ID is valid without raising an exception."""
    return isinstance(class_id, int) and not isinstance(class_id, bool) and class_id in _CANONICAL_ID_TO_CLASS


def is_valid_class_name(class_name: str) -> bool:
    """Check whether a class name or alias is valid without raising an exception."""
    try:
        normalize_class_name(class_name)
        return True
    except (InvalidClassNameError, TypeError):
        return False


def get_empty_count_map() -> Dict[str, int]:
    """Return a fresh dictionary with all nine canonical classes initialized to 0.

    Ensures that every detection result payload explicitly reports all 9 classes,
    even those with zero detected bottles.
    """
    return {name: 0 for name in get_all_class_names()}
