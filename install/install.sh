#!/bin/bash
set -e

INSTALL_DIR="${1:-/opt/coral-libs}"
REPO="https://github.com/thatSFguy/coral-edgetpu-legacy-cpu/raw/main/binaries"

echo "Installing Coral Edge TPU SSSE3 libraries to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

echo "Downloading libedgetpu..."
wget -q "$REPO/libedgetpu.so.1.0" -O "$INSTALL_DIR/libedgetpu.so.1.0"

echo "Downloading tflite_runtime wrapper..."
wget -q "$REPO/_pywrap_tensorflow_interpreter_wrapper.so" \
  -O "$INSTALL_DIR/_pywrap_tensorflow_interpreter_wrapper.so"

echo ""
echo "Done! Files installed to $INSTALL_DIR"
echo ""
echo "Add these lines to your Frigate docker-compose.yml volumes section:"
echo ""
echo "  - $INSTALL_DIR/libedgetpu.so.1.0:/usr/lib/x86_64-linux-gnu/libedgetpu.so.1.0"
echo "  - $INSTALL_DIR/_pywrap_tensorflow_interpreter_wrapper.so:/usr/local/lib/python3.11/dist-packages/tflite_runtime/_pywrap_tensorflow_interpreter_wrapper.so"
