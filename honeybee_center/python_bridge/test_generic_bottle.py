"""Pretrained YOLOv8n ONNX Generic Bottle Detection Verification Script.

Processes the four pilot images in HoneyBottleDataset using an official,
pretrained YOLOv8n COCO ONNX model executed locally on CPU via OpenCV DNN (cv2.dnn).

Detects generic 'bottle' objects (COCO class ID 39, column 43), applies Non-Maximum
Suppression (NMS), transforms letterboxed coordinates back to original image dimensions,
draws bounding boxes on image copies, and saves results to:
    python_bridge/test_output/pilot_detections/
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

import cv2
import numpy as np

# Ensure python_bridge directory is in sys.path
BRIDGE_DIR = Path(__file__).resolve().parent
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from detector.preprocessor import image_to_blob, letterbox_image, unletterbox_bbox
from detector.schemas import BoundingBox

# Configuration Constants
DEFAULT_MODEL_PATH = BRIDGE_DIR / "models" / "yolov8n.onnx"
DEFAULT_DATASET_DIR = Path(r"C:\Users\DeLL\Desktop\HoneyBottleDataset\images")
DEFAULT_OUTPUT_DIR = BRIDGE_DIR / "test_output" / "pilot_detections"

TARGET_INPUT_SHAPE = (640, 640)  # (width, height)
COCO_BOTTLE_CLASS_ID = 39        # 0-indexed COCO class ID for 'bottle'
YOLO8_BOTTLE_COL_INDEX = 43      # 4 box coords [cx, cy, w, h] + 39 = column 43

CONFIDENCE_THRESHOLD = 0.40      # Initial minimum confidence
NMS_IOU_THRESHOLD = 0.45         # Initial IoU threshold for NMS


def load_model(model_path: Path) -> cv2.dnn.Net:
    """Load ONNX model using OpenCV DNN."""
    if not model_path.exists():
        raise FileNotFoundError(f"Model file not found at: {model_path}")
    net = cv2.dnn.readNetFromONNX(str(model_path))
    # Prefer CPU backend
    net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
    net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)
    return net


def detect_bottles_in_image(
    image: np.ndarray,
    net: cv2.dnn.Net,
    conf_threshold: float = CONFIDENCE_THRESHOLD,
    nms_threshold: float = NMS_IOU_THRESHOLD,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """Execute letterboxing, inference, and NMS on a single image.

    Returns:
        Tuple of:
            - List of detected bottle dictionaries containing 'confidence', 'bbox', etc.
            - Timing and metadata dictionary.
    """
    orig_h, orig_w = image.shape[:2]

    # 1. Aspect-ratio preserving letterbox preprocessing
    t_start = time.perf_counter()
    letterboxed, meta = letterbox_image(image, target_shape=TARGET_INPUT_SHAPE, pad_color=(114, 114, 114))
    blob = image_to_blob(letterboxed, swap_rb=True)
    t_prep = time.perf_counter()

    # 2. Forward pass via OpenCV DNN
    net.setInput(blob)
    output = net.forward()  # Expected shape: (1, 84, 8400)
    t_infer = time.perf_counter()

    # 3. Postprocessing & decoding
    # Output layout: output[0] has shape (84, 8400) -> transpose to (8400, 84)
    preds = np.transpose(output[0])

    boxes_letterbox: List[List[int]] = []
    confidences: List[float] = []

    for row in preds:
        bottle_conf = float(row[YOLO8_BOTTLE_COL_INDEX])
        if bottle_conf >= conf_threshold:
            cx, cy, w, h = float(row[0]), float(row[1]), float(row[2]), float(row[3])
            # Convert center-based box to top-left [x1, y1, w, h] for OpenCV NMS
            x1 = cx - (w / 2.0)
            y1 = cy - (h / 2.0)
            boxes_letterbox.append([int(round(x1)), int(round(y1)), int(round(w)), int(round(h))])
            confidences.append(bottle_conf)

    # 4. Non-Maximum Suppression
    indices = cv2.dnn.NMSBoxes(
        boxes_letterbox,
        confidences,
        score_threshold=conf_threshold,
        nms_threshold=nms_threshold,
    )

    detections: List[Dict[str, Any]] = []
    if len(indices) > 0:
        for idx in indices.flatten():
            bx, by, bw, bh = boxes_letterbox[idx]
            conf = confidences[idx]
            # Convert to [x1, y1, x2, y2] in letterbox space
            lb_box = (float(bx), float(by), float(bx + bw), float(by + bh))
            # Reverse letterbox transformation to original image space
            orig_bbox: BoundingBox = unletterbox_bbox(lb_box, meta)

            detections.append({
                "class_id": COCO_BOTTLE_CLASS_ID,
                "class_name": "bottle",
                "confidence": round(conf, 4),
                "bbox": orig_bbox.to_dict(),
                "width": round(orig_bbox.width, 2),
                "height": round(orig_bbox.height, 2),
            })

    t_post = time.perf_counter()

    timing = {
        "prep_ms": round((t_prep - t_start) * 1000, 2),
        "infer_ms": round((t_infer - t_prep) * 1000, 2),
        "post_ms": round((t_post - t_infer) * 1000, 2),
        "total_ms": round((t_post - t_start) * 1000, 2),
    }

    return detections, timing


def draw_detections(
    image: np.ndarray,
    detections: List[Dict[str, Any]],
    box_color: Tuple[int, int, int] = (0, 215, 255),  # Honey gold in BGR
    text_color: Tuple[int, int, int] = (0, 0, 0),
) -> np.ndarray:
    """Draw bounding boxes and confidence badges on a copy of the image."""
    annotated = image.copy()
    for det in detections:
        box = det["bbox"]
        x1, y1, x2, y2 = int(box["x1"]), int(box["y1"]), int(box["x2"]), int(box["y2"])
        conf_str = f"{det['class_name']}: {det['confidence']:.2%}"

        # Draw bounding rectangle
        cv2.rectangle(annotated, (x1, y1), (x2, y2), box_color, thickness=4)

        # Draw filled label badge
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 1.2
        thickness = 2
        (text_w, text_h), baseline = cv2.getTextSize(conf_str, font, font_scale, thickness)

        badge_y1 = max(0, y1 - text_h - 14)
        badge_y2 = y1
        badge_x1 = x1
        badge_x2 = x1 + text_w + 16

        cv2.rectangle(annotated, (badge_x1, badge_y1), (badge_x2, badge_y2), box_color, cv2.FILLED)
        cv2.putText(
            annotated,
            conf_str,
            (badge_x1 + 8, badge_y2 - 6),
            font,
            font_scale,
            text_color,
            thickness=thickness,
            lineType=cv2.LINE_AA,
        )

    return annotated


def run_test(
    model_path: Path = DEFAULT_MODEL_PATH,
    dataset_dir: Path = DEFAULT_DATASET_DIR,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    conf_threshold: float = CONFIDENCE_THRESHOLD,
    nms_threshold: float = NMS_IOU_THRESHOLD,
) -> int:
    """Execute generic bottle detection test on all four 200g pilot images."""
    print("=" * 70)
    print("HONEYBEE CENTER — YOLOV8n ONNX GENERIC BOTTLE DETECTION TEST")
    print("=" * 70)
    print(f"Model Path:         {model_path}")
    print(f"Dataset Directory:  {dataset_dir}")
    print(f"Output Directory:   {output_dir}")
    print(f"Confidence Thresh:  {conf_threshold}")
    print(f"NMS IoU Thresh:     {nms_threshold}")
    print("-" * 70)

    # Validate model
    if not model_path.exists():
        print(f"[ERROR] Model file not found: {model_path}")
        return 1

    net = load_model(model_path)
    print("[SUCCESS] Loaded YOLOv8n ONNX model successfully into OpenCV DNN.")

    # Target images
    image_names = ["200g_001.jpg", "200g_002.jpg", "200g_003.jpg", "200g_004.jpg"]
    output_dir.mkdir(parents=True, exist_ok=True)

    results_summary: Dict[str, Any] = {
        "test_name": "YOLOv8n ONNX Generic Bottle Detection",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": {
            "path": str(model_path),
            "size_bytes": model_path.stat().st_size,
            "target_input_shape": list(TARGET_INPUT_SHAPE),
            "coco_class_id": COCO_BOTTLE_CLASS_ID,
            "confidence_threshold": conf_threshold,
            "nms_threshold": nms_threshold,
        },
        "images": {},
        "summary": {
            "total_images": len(image_names),
            "images_with_detections": 0,
            "total_bottles_detected": 0,
            "mean_inference_ms": 0.0,
        },
    }

    all_infer_times: List[float] = []

    for name in image_names:
        img_path = dataset_dir / name
        if not img_path.exists():
            print(f"[ERROR] Image not found: {img_path}")
            continue

        orig_img = cv2.imread(str(img_path))
        if orig_img is None:
            print(f"[ERROR] Failed to decode image: {img_path}")
            continue

        h, w = orig_img.shape[:2]
        detections, timing = detect_bottles_in_image(
            orig_img,
            net,
            conf_threshold=conf_threshold,
            nms_threshold=nms_threshold,
        )

        all_infer_times.append(timing["infer_ms"])
        num_detected = len(detections)
        if num_detected > 0:
            results_summary["summary"]["images_with_detections"] += 1
            results_summary["summary"]["total_bottles_detected"] += num_detected

        # Save visual output copy (never overwrite original!)
        annotated_img = draw_detections(orig_img, detections)
        out_image_name = f"{Path(name).stem}_detected.jpg"
        out_image_path = output_dir / out_image_name
        cv2.imwrite(str(out_image_path), annotated_img)

        results_summary["images"][name] = {
            "original_path": str(img_path),
            "dimensions": {"width": w, "height": h},
            "bottles_detected": num_detected,
            "detections": detections,
            "timing_ms": timing,
            "annotated_output_path": str(out_image_path),
        }

        print(f"[*] {name}: {num_detected} bottle(s) detected "
              f"(Infer: {timing['infer_ms']}ms, Total: {timing['total_ms']}ms)")
        for idx, det in enumerate(detections, 1):
            bbox = det["bbox"]
            print(f"    #{idx}: {det['class_name']} — Conf: {det['confidence']:.2%} | "
                  f"BBox: [x1={bbox['x1']}, y1={bbox['y1']}, x2={bbox['x2']}, y2={bbox['y2']}] "
                  f"(W={det['width']}, H={det['height']})")

    # Compute overall metrics
    if all_infer_times:
        results_summary["summary"]["mean_inference_ms"] = round(
            float(np.mean(all_infer_times)), 2
        )

    # Save results.json
    results_json_path = output_dir / "results.json"
    with open(results_json_path, "w", encoding="utf-8") as f:
        json.dump(results_summary, f, indent=2)

    print("-" * 70)
    print(f"Results JSON written to: {results_json_path}")
    print(f"Summary: {results_summary['summary']['images_with_detections']}/{len(image_names)} "
          f"images with bottles detected ({results_summary['summary']['total_bottles_detected']} total bottles).")
    print(f"Average CPU Inference Latency: {results_summary['summary']['mean_inference_ms']} ms")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(run_test())
