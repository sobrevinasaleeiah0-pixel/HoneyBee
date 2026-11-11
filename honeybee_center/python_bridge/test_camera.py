"""ESP32-S3-CAM Capture Verification Script.

Requests a single JPEG frame from the ESP32 camera /capture endpoint,
decodes it using OpenCV, displays frame metadata, and saves a local test image.
"""

import sys
from pathlib import Path
import cv2

# Ensure python_bridge directory is in sys.path
BRIDGE_DIR = Path(__file__).resolve().parent
if str(BRIDGE_DIR) not in sys.path:
    sys.path.insert(0, str(BRIDGE_DIR))

from camera.esp32_client import (
    ESP32CameraClient,
    CameraConnectionError,
    CameraResponseError,
    ImageDecodeError,
)
import config


def run_capture_test() -> int:
    camera_url = config.ESP32_CAMERA_URL
    timeout = config.CAMERA_TIMEOUT_SECONDS
    output_dir = config.TEST_OUTPUT_DIR
    output_image_path = output_dir / "esp32_capture.jpg"

    print("=" * 60)
    print("HONEYBEE CENTER — ESP32 CAMERA CAPTURE TEST")
    print("=" * 60)
    print(f"Target Camera URL: {camera_url}")
    print(f"Endpoint:          {camera_url}/capture")
    print(f"Timeout:           {timeout}s")
    print(f"Output File:       {output_image_path}")
    print("-" * 60)

    if "YOUR_ESP32_IP" in camera_url:
        print("[ERROR] Camera URL is set to placeholder 'YOUR_ESP32_IP'.")
        print("Please configure ESP32_CAMERA_URL in python_bridge/.env or set the environment variable.")
        return 1

    client = ESP32CameraClient(base_url=camera_url, timeout=timeout)

    try:
        print("Requesting frame from ESP32 /capture endpoint...")
        image, metadata = client.capture_frame()

        print("[SUCCESS] Frame received and decoded successfully.")
        print(f"HTTP Status Code:  {metadata['status_code']}")
        print(f"JPEG Byte Size:    {metadata['byte_size']:,} bytes")
        print(f"Resolution:        {metadata['width']}x{metadata['height']}")
        print(f"Color Channels:    {metadata['channels']}")
        if metadata.get("x_timestamp"):
            print(f"Camera Timestamp:  {metadata['x_timestamp']}")

        # Ensure output directory exists and save image
        output_dir.mkdir(parents=True, exist_ok=True)
        save_success = cv2.imwrite(str(output_image_path), image)

        if not save_success:
            print(f"[ERROR] cv2.imwrite failed to save image to {output_image_path}")
            return 1

        saved_size = output_image_path.stat().st_size
        print(f"Saved Image Path:  {output_image_path}")
        print(f"Saved File Size:   {saved_size:,} bytes")
        print("=" * 60)
        print("VERIFICATION RESULT: SUCCESS")
        print("=" * 60)
        return 0

    except CameraConnectionError as err:
        print(f"[CAPTURE FAILED] Connection Error: {err}")
        print("-" * 60)
        print("Troubleshooting:")
        print("  1. Verify the ESP32-S3 is powered on and connected to the same Wi-Fi network.")
        print(f"  2. Verify the IP address ({camera_url}) matches the IP printed on the Serial Monitor.")
        print("  3. Ensure no firewall or subnet isolation is blocking port 80.")
        return 1
    except CameraResponseError as err:
        print(f"[CAPTURE FAILED] Camera Response Error: {err}")
        return 1
    except ImageDecodeError as err:
        print(f"[CAPTURE FAILED] Image Decode Error: {err}")
        return 1
    except Exception as err:
        print(f"[CAPTURE FAILED] Unexpected Error: {err}")
        return 1


if __name__ == "__main__":
    sys.exit(run_capture_test())
