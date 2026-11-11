"""ESP32-S3-CAM OV5640 HTTP Client.

Provides an on-demand snapshot client for retrieving and decoding JPEG frames
from the ESP32 CameraWebServer /capture endpoint.
"""

from typing import Dict, Any, Tuple
import cv2
import numpy as np
import requests


class CameraConnectionError(Exception):
    """Raised when the camera cannot be reached (timeout, connection refused, DNS error)."""
    pass


class CameraResponseError(Exception):
    """Raised when the camera returns a non-200 HTTP status code or invalid payload."""
    pass


class ImageDecodeError(Exception):
    """Raised when OpenCV fails to decode the received bytes into an image array."""
    pass


class ESP32CameraClient:
    """Client for retrieving snapshot frames from an ESP32-S3-CAM HTTP server."""

    JPEG_MAGIC_SOI = b"\xff\xd8"
    JPEG_MAGIC_EOI = b"\xff\xd9"

    def __init__(self, base_url: str = "http://192.168.1.100", timeout: float = 5.0) -> None:
        """Initialize the ESP32 Camera client.

        Args:
            base_url: Base HTTP address of the ESP32 camera (e.g., "http://192.168.123.50").
            timeout: HTTP request timeout in seconds.
        """
        self.base_url = self._normalize_url(base_url)
        self.timeout = timeout

    @staticmethod
    def _normalize_url(url: str) -> str:
        url = url.strip().rstrip("/")
        if not url.startswith("http://") and not url.startswith("https://"):
            url = f"http://{url}"
        return url

    def get_capture_url(self) -> str:
        """Return the complete URL for the /capture endpoint."""
        return f"{self.base_url}/capture"

    def get_status_url(self) -> str:
        """Return the complete URL for the /status endpoint."""
        return f"{self.base_url}/status"

    def capture_frame(self) -> Tuple[np.ndarray, Dict[str, Any]]:
        """Request a single snapshot from the ESP32 /capture endpoint and decode it.

        Returns:
            Tuple of:
                - numpy.ndarray: Decoded BGR image matrix from OpenCV.
                - Dict[str, Any]: Capture metadata (status_code, byte_size, width, height, channels, headers).

        Raises:
            CameraConnectionError: If network connection fails or times out.
            CameraResponseError: If HTTP response is not 200 or payload is not JPEG.
            ImageDecodeError: If OpenCV fails to decode the byte stream into an image.
        """
        capture_url = self.get_capture_url()

        try:
            response = requests.get(
                capture_url,
                timeout=self.timeout,
                headers={"Connection": "close", "Accept": "image/jpeg, */*"},
            )
        except requests.exceptions.Timeout as exc:
            raise CameraConnectionError(
                f"Connection timed out while connecting to ESP32 at {capture_url} (timeout={self.timeout}s)"
            ) from exc
        except requests.exceptions.ConnectionError as exc:
            raise CameraConnectionError(
                f"Failed to connect to ESP32 at {capture_url}. Check camera power, Wi-Fi connection, and IP."
            ) from exc
        except requests.exceptions.RequestException as exc:
            raise CameraConnectionError(
                f"HTTP request error while accessing {capture_url}: {exc}"
            ) from exc

        if response.status_code != 200:
            raise CameraResponseError(
                f"ESP32 camera returned HTTP status {response.status_code} for {capture_url}: {response.text[:200]}"
            )

        raw_bytes = response.content
        byte_size = len(raw_bytes)

        if byte_size == 0:
            raise CameraResponseError("ESP32 camera returned an empty response (0 bytes).")

        # Validate JPEG magic Start of Image (SOI) bytes
        if not raw_bytes.startswith(self.JPEG_MAGIC_SOI):
            content_type = response.headers.get("Content-Type", "unknown")
            raise CameraResponseError(
                f"Response is not a valid JPEG. Start bytes: {raw_bytes[:8]!r}, Content-Type: {content_type}"
            )

        # Decode JPEG bytes using OpenCV
        np_arr = np.frombuffer(raw_bytes, dtype=np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        if image is None or image.size == 0:
            raise ImageDecodeError(
                f"OpenCV (cv2.imdecode) failed to decode {byte_size} bytes into an image array."
            )

        height, width, channels = image.shape

        metadata: Dict[str, Any] = {
            "status_code": response.status_code,
            "byte_size": byte_size,
            "width": width,
            "height": height,
            "channels": channels,
            "content_type": response.headers.get("Content-Type", "image/jpeg"),
            "x_timestamp": response.headers.get("X-Timestamp"),
            "camera_url": self.base_url,
        }

        return image, metadata
