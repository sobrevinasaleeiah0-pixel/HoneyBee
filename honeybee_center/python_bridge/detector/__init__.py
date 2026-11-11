"""Honeybee Center Nine-Class AI Detector Package.

Exports canonical class definitions, typed schemas, and preprocessing utilities.
"""

from .classes import (
    CANONICAL_CLASSES,
    CANONICAL_CLASS_NAMES,
    CLASS_ALIASES,
    DetectorClassError,
    InvalidClassIdError,
    InvalidClassNameError,
    class_to_id,
    get_all_class_ids,
    get_all_class_names,
    get_canonical_classes,
    get_empty_count_map,
    id_to_class,
    is_valid_class_id,
    is_valid_class_name,
    normalize_class_name,
)
from .preprocessor import (
    InvalidImageError,
    LetterboxMetadata,
    image_to_blob,
    letterbox_image,
    unletterbox_bbox,
    validate_image,
)
from .schemas import (
    BoundingBox,
    Detection,
    DetectionResult,
    SchemaValidationError,
)

__all__ = [
    # Classes
    "CANONICAL_CLASSES",
    "CANONICAL_CLASS_NAMES",
    "CLASS_ALIASES",
    "DetectorClassError",
    "InvalidClassIdError",
    "InvalidClassNameError",
    "class_to_id",
    "get_all_class_ids",
    "get_all_class_names",
    "get_canonical_classes",
    "get_empty_count_map",
    "id_to_class",
    "is_valid_class_id",
    "is_valid_class_name",
    "normalize_class_name",
    # Schemas
    "BoundingBox",
    "Detection",
    "DetectionResult",
    "SchemaValidationError",
    # Preprocessor
    "InvalidImageError",
    "LetterboxMetadata",
    "image_to_blob",
    "letterbox_image",
    "unletterbox_bbox",
    "validate_image",
]
