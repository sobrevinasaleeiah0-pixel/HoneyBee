"""Typed data structures and validation schemas for 9-Class Object Detection.

Defines schemas for:
    - BoundingBox: Pixel coordinate bounding box with validation and geometry helpers.
    - Detection: Individual detected bottle with class ID, name, confidence, and bbox.
    - DetectionResult: Aggregated result payload including 9-class count map, total count,
      detection list, and metadata.
"""

from dataclasses import dataclass, field
import math
from typing import Any, Dict, List, Optional, Tuple

from .classes import (
    get_all_class_names,
    get_empty_count_map,
    id_to_class,
    is_valid_class_id,
    normalize_class_name,
)


class SchemaValidationError(ValueError):
    """Raised when data structure validation fails."""
    pass


@dataclass(frozen=True)
class BoundingBox:
    """Bounding box in absolute image pixel coordinates [x1, y1, x2, y2].

    Attributes:
        x1: Left horizontal pixel coordinate (>= 0).
        y1: Top vertical pixel coordinate (>= 0).
        x2: Right horizontal pixel coordinate (> x1).
        y2: Bottom vertical pixel coordinate (> y1).
    """
    x1: float
    y1: float
    x2: float
    y2: float

    def __post_init__(self) -> None:
        for val, name in [(self.x1, "x1"), (self.y1, "y1"), (self.x2, "x2"), (self.y2, "y2")]:
            if not isinstance(val, (int, float)) or isinstance(val, bool):
                raise SchemaValidationError(f"BoundingBox {name} must be numeric, got {type(val).__name__}: {val!r}")
            if math.isnan(val) or math.isinf(val):
                raise SchemaValidationError(f"BoundingBox {name} cannot be NaN or Inf, got {val}")

        if self.x1 < 0:
            raise SchemaValidationError(f"BoundingBox x1 cannot be negative: {self.x1}")
        if self.y1 < 0:
            raise SchemaValidationError(f"BoundingBox y1 cannot be negative: {self.y1}")
        if self.x2 <= self.x1:
            raise SchemaValidationError(f"BoundingBox x2 ({self.x2}) must be strictly greater than x1 ({self.x1})")
        if self.y2 <= self.y1:
            raise SchemaValidationError(f"BoundingBox y2 ({self.y2}) must be strictly greater than y1 ({self.y1})")

    @property
    def width(self) -> float:
        """Return width in pixels."""
        return self.x2 - self.x1

    @property
    def height(self) -> float:
        """Return height in pixels."""
        return self.y2 - self.y1

    @property
    def area(self) -> float:
        """Return bounding box area in square pixels."""
        return self.width * self.height

    def validate_bounds(self, image_width: int, image_height: int) -> None:
        """Validate that the bounding box lies completely within the image dimensions.

        Args:
            image_width: Width of image in pixels (must be > 0).
            image_height: Height of image in pixels (must be > 0).

        Raises:
            SchemaValidationError: If coordinates exceed image boundaries.
        """
        if not isinstance(image_width, int) or image_width <= 0:
            raise SchemaValidationError(f"image_width must be positive integer, got {image_width!r}")
        if not isinstance(image_height, int) or image_height <= 0:
            raise SchemaValidationError(f"image_height must be positive integer, got {image_height!r}")

        # Allow slight floating point tolerance for boundary checks (e.g. 1e-4)
        eps = 1e-3
        if self.x2 > image_width + eps:
            raise SchemaValidationError(
                f"BoundingBox x2 ({self.x2:.2f}) exceeds image_width ({image_width})"
            )
        if self.y2 > image_height + eps:
            raise SchemaValidationError(
                f"BoundingBox y2 ({self.y2:.2f}) exceeds image_height ({image_height})"
            )

    def to_dict(self) -> Dict[str, float]:
        """Convert bounding box to dictionary format."""
        return {
            "x1": round(float(self.x1), 2),
            "y1": round(float(self.y1), 2),
            "x2": round(float(self.x2), 2),
            "y2": round(float(self.y2), 2),
        }

    def to_tuple(self) -> Tuple[float, float, float, float]:
        """Convert bounding box to (x1, y1, x2, y2) tuple."""
        return (float(self.x1), float(self.y1), float(self.x2), float(self.y2))

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BoundingBox":
        """Deserialize from dictionary."""
        required = ("x1", "y1", "x2", "y2")
        for key in required:
            if key not in data:
                raise SchemaValidationError(f"BoundingBox dictionary missing required key: {key!r}")
        return cls(
            x1=float(data["x1"]),
            y1=float(data["y1"]),
            x2=float(data["x2"]),
            y2=float(data["y2"]),
        )


@dataclass(frozen=True)
class Detection:
    """Individual detected honey bottle.

    Attributes:
        class_id: Canonical integer class ID (0..8).
        class_name: Canonical class label string (e.g. '250g').
        confidence: Detection confidence score in range [0.0, 1.0].
        bbox: BoundingBox object.
        image_width: Width of image in pixels.
        image_height: Height of image in pixels.
    """
    class_id: int
    class_name: str
    confidence: float
    bbox: BoundingBox
    image_width: int
    image_height: int

    def __post_init__(self) -> None:
        # Validate class_id
        if not is_valid_class_id(self.class_id):
            raise SchemaValidationError(
                f"Invalid class_id: {self.class_id!r}. Must be integer in range 0..8."
            )

        # Validate class_name matches canonical name for class_id
        canonical_name = id_to_class(self.class_id)
        if self.class_name != canonical_name:
            raise SchemaValidationError(
                f"class_name {self.class_name!r} does not match canonical name {canonical_name!r} for class_id {self.class_id}"
            )

        # Validate confidence
        if not isinstance(self.confidence, (int, float)) or isinstance(self.confidence, bool):
            raise SchemaValidationError(
                f"confidence must be numeric, got {type(self.confidence).__name__}: {self.confidence!r}"
            )
        if math.isnan(self.confidence) or math.isinf(self.confidence):
            raise SchemaValidationError(f"confidence cannot be NaN or Inf, got {self.confidence}")
        if not (0.0 <= self.confidence <= 1.0):
            raise SchemaValidationError(
                f"confidence must be in range [0.0, 1.0], got {self.confidence}"
            )

        # Validate bbox type
        if not isinstance(self.bbox, BoundingBox):
            raise SchemaValidationError(
                f"bbox must be an instance of BoundingBox, got {type(self.bbox).__name__}"
            )

        # Validate dimensions and bounds
        if not isinstance(self.image_width, int) or self.image_width <= 0:
            raise SchemaValidationError(
                f"image_width must be positive integer, got {self.image_width!r}"
            )
        if not isinstance(self.image_height, int) or self.image_height <= 0:
            raise SchemaValidationError(
                f"image_height must be positive integer, got {self.image_height!r}"
            )

        self.bbox.validate_bounds(self.image_width, self.image_height)

    def to_dict(self) -> Dict[str, Any]:
        """Serialize detection to dictionary format."""
        return {
            "class_id": self.class_id,
            "class_name": self.class_name,
            "confidence": round(float(self.confidence), 4),
            "bbox": self.bbox.to_dict(),
            "image_width": self.image_width,
            "image_height": self.image_height,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Detection":
        """Deserialize detection from dictionary."""
        required = ("class_id", "class_name", "confidence", "bbox", "image_width", "image_height")
        for key in required:
            if key not in data:
                raise SchemaValidationError(f"Detection dictionary missing required key: {key!r}")

        bbox_data = data["bbox"]
        if isinstance(bbox_data, dict):
            bbox = BoundingBox.from_dict(bbox_data)
        elif isinstance(bbox_data, BoundingBox):
            bbox = bbox_data
        else:
            raise SchemaValidationError(f"Invalid bbox in detection data: {bbox_data!r}")

        return cls(
            class_id=int(data["class_id"]),
            class_name=str(data["class_name"]),
            confidence=float(data["confidence"]),
            bbox=bbox,
            image_width=int(data["image_width"]),
            image_height=int(data["image_height"]),
        )


@dataclass
class DetectionResult:
    """Aggregated detection result payload for one camera capture.

    Attributes:
        detectedSizes: Map of all 9 canonical class names to bottle counts.
        totalDetected: Total count of bottles detected across all classes.
        detections: List of individual Detection instances.
        image_width: Width of scanned frame in pixels.
        image_height: Height of scanned frame in pixels.
        metadata: Optional dictionary of processing metadata (e.g., latency_ms, preprocessor, timestamp).
    """
    detectedSizes: Dict[str, int]
    totalDetected: int
    detections: List[Detection]
    image_width: int
    image_height: int
    metadata: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.validate()

    def validate(self) -> None:
        """Validate internal consistency of the detection result."""
        # 1. Validate image dimensions
        if not isinstance(self.image_width, int) or self.image_width <= 0:
            raise SchemaValidationError(f"image_width must be positive integer, got {self.image_width!r}")
        if not isinstance(self.image_height, int) or self.image_height <= 0:
            raise SchemaValidationError(f"image_height must be positive integer, got {self.image_height!r}")

        # 2. Validate detectedSizes structure: all 9 canonical classes must be present
        if not isinstance(self.detectedSizes, dict):
            raise SchemaValidationError(f"detectedSizes must be a dict, got {type(self.detectedSizes).__name__}")

        canonical_names = set(get_all_class_names())
        given_keys = set(self.detectedSizes.keys())
        missing_keys = canonical_names - given_keys
        if missing_keys:
            raise SchemaValidationError(
                f"detectedSizes map is missing canonical classes: {sorted(missing_keys)}. "
                f"All 9 classes must be present."
            )
        extra_keys = given_keys - canonical_names
        if extra_keys:
            raise SchemaValidationError(
                f"detectedSizes map contains unauthorized class keys: {sorted(extra_keys)}"
            )

        # 3. Validate count values
        for class_name, count in self.detectedSizes.items():
            if not isinstance(count, int) or isinstance(count, bool):
                raise SchemaValidationError(
                    f"Count for {class_name} must be integer, got {type(count).__name__}: {count!r}"
                )
            if count < 0:
                raise SchemaValidationError(
                    f"Count for {class_name} cannot be negative: {count}"
                )

        # 4. Validate totalDetected
        expected_total = sum(self.detectedSizes.values())
        if not isinstance(self.totalDetected, int) or isinstance(self.totalDetected, bool):
            raise SchemaValidationError(
                f"totalDetected must be integer, got {type(self.totalDetected).__name__}: {self.totalDetected!r}"
            )
        if self.totalDetected != expected_total:
            raise SchemaValidationError(
                f"totalDetected ({self.totalDetected}) does not match sum of detectedSizes ({expected_total})"
            )

        # 5. Validate detections list consistency
        if not isinstance(self.detections, list):
            raise SchemaValidationError(
                f"detections must be a list, got {type(self.detections).__name__}"
            )

        if len(self.detections) != self.totalDetected:
            raise SchemaValidationError(
                f"Number of detections in list ({len(self.detections)}) does not match totalDetected ({self.totalDetected})"
            )

        # Check per-class count consistency against individual detections
        counted_by_detections: Dict[str, int] = get_empty_count_map()
        for idx, det in enumerate(self.detections):
            if not isinstance(det, Detection):
                raise SchemaValidationError(
                    f"Detection at index {idx} must be Detection instance, got {type(det).__name__}"
                )
            if det.image_width != self.image_width or det.image_height != self.image_height:
                raise SchemaValidationError(
                    f"Detection at index {idx} dimensions ({det.image_width}x{det.image_height}) "
                    f"do not match result dimensions ({self.image_width}x{self.image_height})"
                )
            counted_by_detections[det.class_name] += 1

        for class_name, expected_count in self.detectedSizes.items():
            actual_count = counted_by_detections[class_name]
            if actual_count != expected_count:
                raise SchemaValidationError(
                    f"Count mismatch for class {class_name!r}: detectedSizes specifies {expected_count}, "
                    f"but detections list contains {actual_count} items."
                )

    @classmethod
    def from_detections(
        cls,
        detections: List[Detection],
        image_width: int,
        image_height: int,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> "DetectionResult":
        """Factory method to construct and validate DetectionResult from a list of Detection instances.

        Automatically computes detectedSizes count map (with all 9 classes) and totalDetected.
        """
        count_map = get_empty_count_map()
        for det in detections:
            count_map[det.class_name] += 1

        total = len(detections)
        return cls(
            detectedSizes=count_map,
            totalDetected=total,
            detections=list(detections),
            image_width=image_width,
            image_height=image_height,
            metadata=dict(metadata or {}),
        )

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary matching the Honeybee Center Firebase /scan_results contract."""
        return {
            "detectedSizes": dict(self.detectedSizes),
            "totalDetected": self.totalDetected,
            "detections": [d.to_dict() for d in self.detections],
            "image_width": self.image_width,
            "image_height": self.image_height,
            "metadata": dict(self.metadata),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "DetectionResult":
        """Deserialize DetectionResult from dictionary."""
        required = ("detectedSizes", "totalDetected", "detections", "image_width", "image_height")
        for key in required:
            if key not in data:
                raise SchemaValidationError(f"DetectionResult dictionary missing required key: {key!r}")

        raw_detections = data["detections"]
        if not isinstance(raw_detections, list):
            raise SchemaValidationError(f"detections must be a list, got {type(raw_detections).__name__}")

        detections = [Detection.from_dict(d) for d in raw_detections]
        detected_sizes = {str(k): int(v) for k, v in data["detectedSizes"].items()}

        return cls(
            detectedSizes=detected_sizes,
            totalDetected=int(data["totalDetected"]),
            detections=detections,
            image_width=int(data["image_width"]),
            image_height=int(data["image_height"]),
            metadata=dict(data.get("metadata", {})),
        )
