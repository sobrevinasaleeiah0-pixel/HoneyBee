"""Model-independent image preprocessing and letterboxing utilities for Honeybee Center.

Provides:
    - LetterboxMetadata: Transformation parameters recording scale and padding.
    - letterbox_image: Aspect-ratio-preserving resize and padding for input frames.
    - unletterbox_bbox: Reverse coordinate transformation mapping model output boxes
      back to original camera frame coordinates.
    - validate_image: Strict validation for OpenCV BGR NumPy images.
    - image_to_blob: Helper converting BGR uint8 images to NCHW normalized float32 tensors.
"""

from dataclasses import dataclass
from typing import Any, Tuple, Union

import cv2
import numpy as np

from .schemas import BoundingBox, SchemaValidationError


class InvalidImageError(ValueError):
    """Raised when an input image fails dimension, channel, or type validation."""
    pass


@dataclass(frozen=True)
class LetterboxMetadata:
    """Transformation metadata recording scale and offsets applied during letterboxing.

    Attributes:
        original_width: Width of the original input image before letterboxing.
        original_height: Height of the original input image before letterboxing.
        target_width: Width of the output padded letterbox image.
        target_height: Height of the output padded letterbox image.
        scale: Uniform scaling factor applied to the original image dimensions.
        pad_x: Left horizontal padding in pixels.
        pad_y: Top vertical padding in pixels.
        unpadded_width: Scaled width of image content before padding.
        unpadded_height: Scaled height of image content before padding.
    """
    original_width: int
    original_height: int
    target_width: int
    target_height: int
    scale: float
    pad_x: int
    pad_y: int
    unpadded_width: int
    unpadded_height: int


def validate_image(image: Any) -> None:
    """Validate that the input is a non-empty 3-channel uint8 OpenCV BGR NumPy array.

    Args:
        image: Candidate image object.

    Raises:
        InvalidImageError: If the input is not a valid OpenCV image array.
    """
    if image is None:
        raise InvalidImageError("Input image is None.")

    if not isinstance(image, np.ndarray):
        raise InvalidImageError(f"Input image must be a numpy.ndarray, got {type(image).__name__}")

    if image.size == 0:
        raise InvalidImageError("Input image is empty (size == 0).")

    if image.dtype != np.uint8:
        raise InvalidImageError(
            f"Input image must have dtype uint8, got {image.dtype}"
        )

    if image.ndim != 3:
        raise InvalidImageError(
            f"Input image must have 3 dimensions (H, W, C), got {image.ndim} dimensions (shape={image.shape})"
        )

    h, w, c = image.shape

    if h <= 0 or w <= 0:
        raise InvalidImageError(f"Invalid image dimensions: height={h}, width={w}")

    if c != 3:
        raise InvalidImageError(
            f"Input image must have exactly 3 color channels (BGR), got {c} channels"
        )


def letterbox_image(
    image: np.ndarray,
    target_shape: Tuple[int, int] = (640, 640),
    pad_color: Tuple[int, int, int] = (114, 114, 114),
) -> Tuple[np.ndarray, LetterboxMetadata]:
    """Resize and pad image to target dimensions while strictly preserving aspect ratio.

    The image is scaled uniformly so its longest dimension matches the target bounding box,
    then centered with constant-color borders added to fill remaining space.

    Args:
        image: Source OpenCV BGR image array (H, W, 3).
        target_shape: Desired output dimensions as (target_width, target_height). Default (640, 640).
        pad_color: BGR tuple for border fill. Defaults to (114, 114, 114).

    Returns:
        Tuple of:
            - np.ndarray: Letterboxed image of shape (target_height, target_width, 3) in uint8.
            - LetterboxMetadata: Transformation parameters needed for reverse coordinate mapping.

    Raises:
        InvalidImageError: If the input image is invalid.
        ValueError: If target_shape is invalid.
    """
    validate_image(image)

    if not isinstance(target_shape, (tuple, list)) or len(target_shape) != 2:
        raise ValueError(f"target_shape must be a tuple of (target_width, target_height), got {target_shape!r}")

    target_w, target_h = int(target_shape[0]), int(target_shape[1])
    if target_w <= 0 or target_h <= 0:
        raise ValueError(f"target_shape dimensions must be positive integers, got {target_shape!r}")

    orig_h, orig_w = image.shape[:2]

    # Calculate uniform scaling factor
    scale = min(target_w / orig_w, target_h / orig_h)

    # Scaled dimensions without padding
    unpad_w = int(round(orig_w * scale))
    unpad_h = int(round(orig_h * scale))

    # Compute padding to center image
    pad_w = target_w - unpad_w
    pad_h = target_h - unpad_h

    pad_left = pad_w // 2
    pad_right = pad_w - pad_left
    pad_top = pad_h // 2
    pad_bottom = pad_h - pad_top

    # Resize image if dimensions differ
    if (orig_w, orig_h) != (unpad_w, unpad_h):
        resized = cv2.resize(image, (unpad_w, unpad_h), interpolation=cv2.INTER_LINEAR)
    else:
        resized = image.copy()

    # Apply constant border
    letterboxed = cv2.copyMakeBorder(
        resized,
        top=pad_top,
        bottom=pad_bottom,
        left=pad_left,
        right=pad_right,
        borderType=cv2.BORDER_CONSTANT,
        value=pad_color,
    )

    metadata = LetterboxMetadata(
        original_width=orig_w,
        original_height=orig_h,
        target_width=target_w,
        target_height=target_h,
        scale=scale,
        pad_x=pad_left,
        pad_y=pad_top,
        unpadded_width=unpad_w,
        unpadded_height=unpad_h,
    )

    return letterboxed, metadata


def unletterbox_bbox(
    bbox: Union[BoundingBox, Tuple[float, float, float, float], list],
    metadata: LetterboxMetadata,
) -> BoundingBox:
    """Transform bounding box coordinates from letterboxed image space back to original camera frame coordinates.

    Args:
        bbox: Bounding box in letterboxed space. Can be a BoundingBox instance
              or a tuple/list of (x1, y1, x2, y2).
        metadata: LetterboxMetadata produced by letterbox_image().

    Returns:
        BoundingBox in original frame coordinates, clipped to original frame boundaries.

    Raises:
        SchemaValidationError: If coordinates cannot be mapped or bounding box is invalid.
    """
    if isinstance(bbox, BoundingBox):
        bx1, by1, bx2, by2 = bbox.x1, bbox.y1, bbox.x2, bbox.y2
    elif isinstance(bbox, (tuple, list)) and len(bbox) == 4:
        bx1, by1, bx2, by2 = float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3])
    else:
        raise SchemaValidationError(f"bbox must be BoundingBox or 4-element sequence, got {type(bbox).__name__}")

    if metadata.scale <= 0:
        raise SchemaValidationError(f"Invalid letterbox metadata scale: {metadata.scale}")

    # Reverse offset and scale
    orig_x1 = (bx1 - metadata.pad_x) / metadata.scale
    orig_y1 = (by1 - metadata.pad_y) / metadata.scale
    orig_x2 = (bx2 - metadata.pad_x) / metadata.scale
    orig_y2 = (by2 - metadata.pad_y) / metadata.scale

    # Clip to original image boundaries
    orig_w = float(metadata.original_width)
    orig_h = float(metadata.original_height)

    clip_x1 = max(0.0, min(orig_x1, orig_w))
    clip_y1 = max(0.0, min(orig_y1, orig_h))
    clip_x2 = max(0.0, min(orig_x2, orig_w))
    clip_y2 = max(0.0, min(orig_y2, orig_h))

    # Guard against collapsed degenerate box after clipping
    if clip_x2 <= clip_x1:
        # Enforce minimal width if box had positive width originally
        if bx2 > bx1 and clip_x1 < orig_w:
            clip_x2 = min(orig_w, clip_x1 + 1.0)
        else:
            raise SchemaValidationError(
                f"Unletterboxed bounding box collapsed horizontally: x1={clip_x1}, x2={clip_x2}"
            )

    if clip_y2 <= clip_y1:
        if by2 > by1 and clip_y1 < orig_h:
            clip_y2 = min(orig_h, clip_y1 + 1.0)
        else:
            raise SchemaValidationError(
                f"Unletterboxed bounding box collapsed vertically: y1={clip_y1}, y2={clip_y2}"
            )

    return BoundingBox(x1=clip_x1, y1=clip_y1, x2=clip_x2, y2=clip_y2)


def image_to_blob(image: np.ndarray, swap_rb: bool = True) -> np.ndarray:
    """Convert uint8 BGR image to normalized float32 NCHW tensor layout.

    Standard preparation for OpenCV DNN (cv2.dnn) or ONNX Runtime inference:
        - Layout: (1, 3, H, W)
        - Data type: np.float32
        - Range: [0.0, 1.0]

    Args:
        image: Preprocessed (e.g. letterboxed) OpenCV image array (H, W, 3).
        swap_rb: If True, convert BGR to RGB. Default True.

    Returns:
        np.ndarray: 4D tensor with shape (1, 3, H, W) in float32.
    """
    validate_image(image)

    # Swap BGR -> RGB if requested
    if swap_rb:
        rgb_img = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    else:
        rgb_img = image

    # Scale to [0.0, 1.0] float32
    norm_img = rgb_img.astype(np.float32) / 255.0

    # Transpose HWC (height, width, channels) -> CHW (channels, height, width)
    chw_img = np.transpose(norm_img, (2, 0, 1))

    # Add batch dimension -> (1, C, H, W)
    blob = np.expand_dims(chw_img, axis=0)

    return np.ascontiguousarray(blob, dtype=np.float32)
