"""Offline unit tests for Honeybee Center Foundational Nine-Class Detection Modules.

Tests:
    1. Nine canonical class mappings (IDs 0..8).
    2. Strict 650g vs 660g separation.
    3. 1000g / 1kg alias resolution.
    4. Invalid class IDs and labels.
    5. Immutable class mapping protection.
    6. BoundingBox validation and coordinate boundaries.
    7. Detection schema validation (confidence bounds, ID/name agreement).
    8. DetectionResult count consistency and all-9-class enforcement.
    9. Empty detection result handling.
    10. Serialization and deserialization (to_dict / from_dict).
    11. Preprocessor validation (rejecting None, empty, 2D, 4-channel, float arrays).
    12. QVGA (320x240) letterbox preprocessing with synthetic arrays.
    13. VGA (640x480) letterbox preprocessing with synthetic arrays.
    14. Letterbox aspect ratio preservation.
    15. Reverse coordinate transformation (unletterbox_bbox round-trip).
    16. Normalization and blob generation (NCHW float32).

STRICT SAFETY:
    Zero network access, zero ESP32 calls, zero Firebase/Supabase calls.
    Uses synthetic NumPy arrays exclusively.
"""

import sys
import unittest
from pathlib import Path
import numpy as np

# Ensure python_bridge is in sys.path
BRIDGE_DIR = Path(__file__).resolve().parent
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from detector.classes import (
    CANONICAL_CLASSES,
    CANONICAL_CLASS_NAMES,
    CLASS_ALIASES,
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
from detector.schemas import (
    BoundingBox,
    Detection,
    DetectionResult,
    SchemaValidationError,
)
from detector.preprocessor import (
    InvalidImageError,
    LetterboxMetadata,
    image_to_blob,
    letterbox_image,
    unletterbox_bbox,
    validate_image,
)


class TestCanonicalClasses(unittest.TestCase):
    """Test suite for detector.classes module."""

    EXPECTED_CLASSES = {
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

    def test_all_nine_classes_present_and_exact(self):
        """Verify that exactly nine canonical classes exist with expected IDs and labels."""
        self.assertEqual(len(CANONICAL_CLASSES), 9)
        for class_id, expected_name in self.EXPECTED_CLASSES.items():
            self.assertEqual(id_to_class(class_id), expected_name)
            self.assertEqual(class_to_id(expected_name), class_id)
            self.assertTrue(is_valid_class_id(class_id))
            self.assertTrue(is_valid_class_name(expected_name))

    def test_class_id_and_name_tuples(self):
        """Verify ordered helper tuples get_all_class_ids and get_all_class_names."""
        self.assertEqual(get_all_class_ids(), (0, 1, 2, 3, 4, 5, 6, 7, 8))
        self.assertEqual(
            get_all_class_names(),
            ("200g", "250g", "350g", "400g", "500g", "650g", "660g", "1000g", "1350g"),
        )

    def test_strict_distinction_650g_and_660g(self):
        """Verify that 650g (Wild) and 660g (Cultured) remain strictly distinct classes."""
        id_650 = class_to_id("650g")
        id_660 = class_to_id("660g")
        self.assertEqual(id_650, 5)
        self.assertEqual(id_660, 6)
        self.assertNotEqual(id_650, id_660)
        self.assertEqual(id_to_class(5), "650g")
        self.assertEqual(id_to_class(6), "660g")

    def test_1000g_and_1kg_alias_resolution(self):
        """Verify that 1kg resolves cleanly to canonical class 1000g (ID 7)."""
        self.assertEqual(normalize_class_name("1kg"), "1000g")
        self.assertEqual(normalize_class_name("1 kg"), "1000g")
        self.assertEqual(normalize_class_name("1.0kg"), "1000g")
        self.assertEqual(normalize_class_name("1000g"), "1000g")
        self.assertEqual(class_to_id("1kg"), 7)
        self.assertEqual(class_to_id("1000g"), 7)
        self.assertTrue(is_valid_class_name("1kg"))

    def test_invalid_class_ids_rejected(self):
        """Verify out-of-range, negative, and invalid type IDs raise InvalidClassIdError."""
        for invalid_id in [-1, 9, 10, 100, 999]:
            with self.assertRaises(InvalidClassIdError):
                id_to_class(invalid_id)
            self.assertFalse(is_valid_class_id(invalid_id))

        # Booleans and floats must be rejected
        for bad_type in [True, False, 1.5, "1", None]:
            with self.assertRaises(InvalidClassIdError):
                id_to_class(bad_type)
            self.assertFalse(is_valid_class_id(bad_type))

    def test_invalid_class_names_rejected(self):
        """Verify unknown names and unauthorized aliases raise InvalidClassNameError."""
        for invalid_name in ["unknown", "honey", "2kg", "750g", "500", "bottle"]:
            with self.assertRaises(InvalidClassNameError):
                class_to_id(invalid_name)
            with self.assertRaises(InvalidClassNameError):
                normalize_class_name(invalid_name)
            self.assertFalse(is_valid_class_name(invalid_name))

        # Non-string types must be rejected
        for bad_type in [123, None, [], {}]:
            with self.assertRaises(InvalidClassNameError):
                class_to_id(bad_type)

    def test_immutable_mappings_cannot_be_mutated(self):
        """Verify CANONICAL_CLASSES and CANONICAL_CLASS_NAMES cannot be modified."""
        with self.assertRaises(TypeError):
            CANONICAL_CLASSES[9] = "999g"
        with self.assertRaises(TypeError):
            CANONICAL_CLASS_NAMES["999g"] = 9

    def test_empty_count_map(self):
        """Verify get_empty_count_map initializes all 9 classes to 0."""
        count_map = get_empty_count_map()
        self.assertEqual(len(count_map), 9)
        for name in get_all_class_names():
            self.assertIn(name, count_map)
            self.assertEqual(count_map[name], 0)


class TestSchemas(unittest.TestCase):
    """Test suite for detector.schemas module."""

    def test_bounding_box_valid(self):
        """Verify valid bounding box initialization, dimensions, and area."""
        bbox = BoundingBox(x1=10.0, y1=20.0, x2=110.0, y2=220.0)
        self.assertEqual(bbox.x1, 10.0)
        self.assertEqual(bbox.y1, 20.0)
        self.assertEqual(bbox.x2, 110.0)
        self.assertEqual(bbox.y2, 220.0)
        self.assertEqual(bbox.width, 100.0)
        self.assertEqual(bbox.height, 200.0)
        self.assertEqual(bbox.area, 20000.0)
        # Verify serialization
        self.assertEqual(bbox.to_dict(), {"x1": 10.0, "y1": 20.0, "x2": 110.0, "y2": 220.0})
        self.assertEqual(bbox.to_tuple(), (10.0, 20.0, 110.0, 220.0))

    def test_bounding_box_invalid_geometry(self):
        """Verify degenerate and inverted coordinates raise SchemaValidationError."""
        with self.assertRaises(SchemaValidationError):
            BoundingBox(x1=100.0, y1=20.0, x2=50.0, y2=120.0)  # x2 <= x1
        with self.assertRaises(SchemaValidationError):
            BoundingBox(x1=10.0, y1=120.0, x2=50.0, y2=50.0)   # y2 <= y1
        with self.assertRaises(SchemaValidationError):
            BoundingBox(x1=-5.0, y1=10.0, x2=50.0, y2=50.0)   # negative x1
        with self.assertRaises(SchemaValidationError):
            BoundingBox(x1=10.0, y1=10.0, x2=10.0, y2=50.0)   # zero width
        with self.assertRaises(SchemaValidationError):
            BoundingBox(x1=float("nan"), y1=10.0, x2=50.0, y2=50.0)

    def test_bounding_box_bounds_validation(self):
        """Verify validate_bounds enforces image boundaries."""
        bbox = BoundingBox(x1=0.0, y1=0.0, x2=640.0, y2=480.0)
        bbox.validate_bounds(image_width=640, image_height=480)  # Exact match passes

        out_bbox = BoundingBox(x1=0.0, y1=0.0, x2=641.0, y2=480.0)
        with self.assertRaises(SchemaValidationError):
            out_bbox.validate_bounds(image_width=640, image_height=480)

    def test_detection_valid(self):
        """Verify valid Detection instance creation and serialization."""
        bbox = BoundingBox(x1=50.0, y1=60.0, x2=150.0, y2=260.0)
        det = Detection(
            class_id=1,
            class_name="250g",
            confidence=0.9234,
            bbox=bbox,
            image_width=640,
            image_height=480,
        )
        self.assertEqual(det.class_id, 1)
        self.assertEqual(det.class_name, "250g")
        self.assertAlmostEqual(det.confidence, 0.9234, places=4)
        det_dict = det.to_dict()
        self.assertEqual(det_dict["class_id"], 1)
        self.assertEqual(det_dict["class_name"], "250g")

        # Round-trip deserialization
        det_from_dict = Detection.from_dict(det_dict)
        self.assertEqual(det, det_from_dict)

    def test_detection_mismatched_id_and_name_rejected(self):
        """Verify Detection rejects class_id that does not correspond to class_name."""
        bbox = BoundingBox(x1=50.0, y1=60.0, x2=150.0, y2=260.0)
        with self.assertRaises(SchemaValidationError):
            Detection(
                class_id=1,  # 1 is 250g
                class_name="500g",  # Mismatch!
                confidence=0.9,
                bbox=bbox,
                image_width=640,
                image_height=480,
            )

    def test_detection_confidence_boundaries(self):
        """Verify confidence must be in range [0.0, 1.0]."""
        bbox = BoundingBox(x1=10.0, y1=10.0, x2=50.0, y2=50.0)
        # Boundaries 0.0 and 1.0 are valid
        Detection(class_id=0, class_name="200g", confidence=0.0, bbox=bbox, image_width=640, image_height=480)
        Detection(class_id=0, class_name="200g", confidence=1.0, bbox=bbox, image_width=640, image_height=480)

        # Invalid confidences
        with self.assertRaises(SchemaValidationError):
            Detection(class_id=0, class_name="200g", confidence=-0.01, bbox=bbox, image_width=640, image_height=480)
        with self.assertRaises(SchemaValidationError):
            Detection(class_id=0, class_name="200g", confidence=1.001, bbox=bbox, image_width=640, image_height=480)
        with self.assertRaises(SchemaValidationError):
            Detection(class_id=0, class_name="200g", confidence=float("nan"), bbox=bbox, image_width=640, image_height=480)

    def test_detection_result_empty(self):
        """Verify DetectionResult handles zero-detection frames cleanly."""
        empty_result = DetectionResult.from_detections(
            detections=[],
            image_width=640,
            image_height=480,
            metadata={"status": "OK"},
        )
        self.assertEqual(empty_result.totalDetected, 0)
        self.assertEqual(len(empty_result.detections), 0)
        self.assertEqual(len(empty_result.detectedSizes), 9)
        for class_name, count in empty_result.detectedSizes.items():
            self.assertEqual(count, 0)

        # Check serialization
        res_dict = empty_result.to_dict()
        self.assertEqual(res_dict["totalDetected"], 0)
        self.assertEqual(res_dict["image_width"], 640)
        self.assertEqual(res_dict["image_height"], 480)

    def test_detection_result_with_multiple_classes(self):
        """Verify DetectionResult aggregates counts across multiple bottle classes."""
        det1 = Detection(class_id=1, class_name="250g", confidence=0.91,
                         bbox=BoundingBox(x1=10, y1=10, x2=50, y2=100), image_width=640, image_height=480)
        det2 = Detection(class_id=1, class_name="250g", confidence=0.88,
                         bbox=BoundingBox(x1=60, y1=10, x2=100, y2=100), image_width=640, image_height=480)
        det3 = Detection(class_id=4, class_name="500g", confidence=0.95,
                         bbox=BoundingBox(x1=120, y1=10, x2=180, y2=140), image_width=640, image_height=480)
        det4 = Detection(class_id=7, class_name="1000g", confidence=0.89,
                         bbox=BoundingBox(x1=200, y1=10, x2=280, y2=200), image_width=640, image_height=480)

        result = DetectionResult.from_detections(
            detections=[det1, det2, det3, det4],
            image_width=640,
            image_height=480,
        )

        self.assertEqual(result.totalDetected, 4)
        self.assertEqual(result.detectedSizes["250g"], 2)
        self.assertEqual(result.detectedSizes["500g"], 1)
        self.assertEqual(result.detectedSizes["1000g"], 1)
        self.assertEqual(result.detectedSizes["200g"], 0)
        self.assertEqual(result.detectedSizes["650g"], 0)
        self.assertEqual(result.detectedSizes["660g"], 0)

        # Round-trip serialization
        res_dict = result.to_dict()
        deserialized = DetectionResult.from_dict(res_dict)
        self.assertEqual(result.totalDetected, deserialized.totalDetected)
        self.assertEqual(result.detectedSizes, deserialized.detectedSizes)
        self.assertEqual(len(result.detections), len(deserialized.detections))

    def test_detection_result_inconsistency_rejected(self):
        """Verify DetectionResult rejects count mismatches and missing classes."""
        # 1. Total count mismatch
        counts = get_empty_count_map()
        counts["250g"] = 2
        with self.assertRaises(SchemaValidationError):
            DetectionResult(
                detectedSizes=counts,
                totalDetected=5,  # Mismatch: should be 2!
                detections=[],
                image_width=640,
                image_height=480,
            )

        # 2. Missing class in detectedSizes
        incomplete_counts = {"250g": 0, "500g": 0}
        with self.assertRaises(SchemaValidationError):
            DetectionResult(
                detectedSizes=incomplete_counts,
                totalDetected=0,
                detections=[],
                image_width=640,
                image_height=480,
            )


class TestPreprocessor(unittest.TestCase):
    """Test suite for detector.preprocessor module."""

    def test_image_validation_rejections(self):
        """Verify validate_image rejects invalid, empty, or wrong-format inputs."""
        # None
        with self.assertRaises(InvalidImageError):
            validate_image(None)

        # Non-numpy
        with self.assertRaises(InvalidImageError):
            validate_image("not an image")

        # Empty array
        with self.assertRaises(InvalidImageError):
            validate_image(np.array([], dtype=np.uint8))

        # 2D Grayscale
        with self.assertRaises(InvalidImageError):
            validate_image(np.zeros((480, 640), dtype=np.uint8))

        # 4-Channel RGBA
        with self.assertRaises(InvalidImageError):
            validate_image(np.zeros((480, 640, 4), dtype=np.uint8))

        # Float32 array
        with self.assertRaises(InvalidImageError):
            validate_image(np.zeros((480, 640, 3), dtype=np.float32))

        # Zero dimension
        with self.assertRaises(InvalidImageError):
            validate_image(np.zeros((0, 640, 3), dtype=np.uint8))

    def test_qvga_320x240_letterbox(self):
        """Verify letterboxing a synthetic QVGA 320x240 image to 640x640."""
        # Synthetic QVGA image
        qvga = np.full((240, 320, 3), fill_value=50, dtype=np.uint8)
        letterboxed, meta = letterbox_image(qvga, target_shape=(640, 640), pad_color=(114, 114, 114))

        # Shape verification
        self.assertEqual(letterboxed.shape, (640, 640, 3))
        self.assertEqual(letterboxed.dtype, np.uint8)

        # Aspect ratio math: 320x240 scaled by min(640/320=2.0, 640/240=2.666) -> scale = 2.0
        self.assertEqual(meta.scale, 2.0)
        self.assertEqual(meta.original_width, 320)
        self.assertEqual(meta.original_height, 240)
        self.assertEqual(meta.unpadded_width, 640)
        self.assertEqual(meta.unpadded_height, 480)
        self.assertEqual(meta.pad_x, 0)
        self.assertEqual(meta.pad_y, 80)  # (640 - 480) // 2

        # Verify border padding color at top/bottom rows
        np.testing.assert_array_equal(letterboxed[0, 0], [114, 114, 114])
        np.testing.assert_array_equal(letterboxed[79, 320], [114, 114, 114])
        # Verify content color inside active area
        np.testing.assert_array_equal(letterboxed[80, 320], [50, 50, 50])

    def test_vga_640x480_letterbox(self):
        """Verify letterboxing a synthetic VGA 640x480 image to 640x640."""
        vga = np.full((480, 640, 3), fill_value=75, dtype=np.uint8)
        letterboxed, meta = letterbox_image(vga, target_shape=(640, 640), pad_color=(114, 114, 114))

        self.assertEqual(letterboxed.shape, (640, 640, 3))
        # Scale: min(640/640=1.0, 640/480=1.333) -> scale = 1.0
        self.assertEqual(meta.scale, 1.0)
        self.assertEqual(meta.original_width, 640)
        self.assertEqual(meta.original_height, 480)
        self.assertEqual(meta.unpadded_width, 640)
        self.assertEqual(meta.unpadded_height, 480)
        self.assertEqual(meta.pad_x, 0)
        self.assertEqual(meta.pad_y, 80)

        # Padding checks
        np.testing.assert_array_equal(letterboxed[0, 0], [114, 114, 114])
        np.testing.assert_array_equal(letterboxed[80, 320], [75, 75, 75])

    def test_non_standard_aspect_ratio_letterbox(self):
        """Verify letterboxing a tall aspect-ratio image (e.g. 400x200)."""
        tall = np.zeros((400, 200, 3), dtype=np.uint8)
        letterboxed, meta = letterbox_image(tall, target_shape=(640, 640))

        # Scale = min(640/200=3.2, 640/400=1.6) -> scale = 1.6
        self.assertEqual(meta.scale, 1.6)
        self.assertEqual(meta.unpadded_width, 320)  # 200 * 1.6
        self.assertEqual(meta.unpadded_height, 640) # 400 * 1.6
        self.assertEqual(meta.pad_x, 160)           # (640 - 320) // 2
        self.assertEqual(meta.pad_y, 0)             # (640 - 640) // 2
        self.assertEqual(letterboxed.shape, (640, 640, 3))

    def test_reverse_coordinate_transformation(self):
        """Verify unletterbox_bbox maps letterboxed coordinates back to original image space."""
        vga = np.zeros((480, 640, 3), dtype=np.uint8)
        _, meta = letterbox_image(vga, target_shape=(640, 640))

        # Suppose a detector finds a box in letterbox space (640x640):
        # Letterbox space: content starts at y=80.
        # Box from y=100 to y=300, x=50 to x=250
        letterbox_bbox = BoundingBox(x1=50.0, y1=100.0, x2=250.0, y2=300.0)

        unletterboxed = unletterbox_bbox(letterbox_bbox, meta)

        # In original VGA space:
        # scale = 1.0, pad_x = 0, pad_y = 80
        # x1 = (50 - 0) / 1.0 = 50.0
        # y1 = (100 - 80) / 1.0 = 20.0
        # x2 = (250 - 0) / 1.0 = 250.0
        # y2 = (300 - 80) / 1.0 = 220.0
        self.assertAlmostEqual(unletterboxed.x1, 50.0, places=2)
        self.assertAlmostEqual(unletterboxed.y1, 20.0, places=2)
        self.assertAlmostEqual(unletterboxed.x2, 250.0, places=2)
        self.assertAlmostEqual(unletterboxed.y2, 220.0, places=2)

    def test_reverse_coordinate_transformation_clipping(self):
        """Verify unletterbox_bbox clips coordinates that land in padding area."""
        vga = np.zeros((480, 640, 3), dtype=np.uint8)
        _, meta = letterbox_image(vga, target_shape=(640, 640))

        # Box overlapping top padding (y < 80) and exceeding width (x > 640)
        out_of_bounds_box = BoundingBox(x1=10.0, y1=20.0, x2=650.0, y2=400.0)
        clipped = unletterbox_bbox(out_of_bounds_box, meta)

        # y1 was in padding (< 80) -> should be clipped to 0.0
        self.assertEqual(clipped.y1, 0.0)
        # x2 was 650 -> should be clipped to original_width (640.0)
        self.assertEqual(clipped.x2, 640.0)

    def test_image_to_blob_tensor_conversion(self):
        """Verify image_to_blob produces NCHW float32 tensor scaled to [0.0, 1.0]."""
        test_img = np.zeros((640, 640, 3), dtype=np.uint8)
        test_img[0, 0] = [255, 128, 0]  # BGR

        blob = image_to_blob(test_img, swap_rb=True)

        self.assertEqual(blob.shape, (1, 3, 640, 640))
        self.assertEqual(blob.dtype, np.float32)
        # Check BGR -> RGB swap on pixel [0, 0]:
        # BGR [255, 128, 0] -> RGB [0, 128, 255]
        # Scaled: [0.0, 128/255, 1.0]
        self.assertAlmostEqual(blob[0, 0, 0, 0], 0.0, places=3)          # R
        self.assertAlmostEqual(blob[0, 1, 0, 0], 128.0 / 255.0, places=3) # G
        self.assertAlmostEqual(blob[0, 2, 0, 0], 1.0, places=3)          # B


if __name__ == "__main__":
    unittest.main(verbosity=2)
