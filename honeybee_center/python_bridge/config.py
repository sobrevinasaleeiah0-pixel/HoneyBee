"""Configuration module for the Honeybee Center Python AI Bridge."""

import os
from pathlib import Path
from dotenv import load_dotenv

# Base directory for the python_bridge package
BRIDGE_DIR = Path(__file__).resolve().parent

# Load optional .env file if present in python_bridge or workspace
load_dotenv(BRIDGE_DIR / ".env")

# Camera connection configuration
ESP32_CAMERA_URL = os.getenv("ESP32_CAMERA_URL", "http://192.168.1.100").strip()
CAMERA_TIMEOUT_SECONDS = float(os.getenv("CAMERA_TIMEOUT_SECONDS", "5.0"))

# Output directories
TEST_OUTPUT_DIR = Path(os.getenv("TEST_OUTPUT_DIR", str(BRIDGE_DIR / "test_output")))
