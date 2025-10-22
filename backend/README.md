Smart CCTV backend (YOLOv8 + brightness)

This folder contains a small FastAPI service that accepts image uploads and returns YOLOv8 detections plus a simple brightness estimate (normalized 0..1 and a 3-category label).

Quick start (local)

1. Create a virtual environment and activate it (recommended):

   python -m venv .venv
   .venv\Scripts\Activate.ps1 # on PowerShell

2. Install dependencies:

   pip install -r requirements.txt

3. Download a YOLOv8 model if you don't have one. The server expects `yolov8n.pt` in the working directory. You can download the official pretrained small model from Ultralytics or export a trained model.

4. Run the server:

   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

API

POST /detect

- Form field: `image` file (multipart/form-data)
- Response: JSON with fields: `brightness` (0..1), `brightness_category` (Very dark/Shallow/Normal), `people_count`, `boxes` (array of normalized bbox + class + confidence)

Example curl

curl -X POST "http://localhost:8000/detect" -F "image=@myphoto.jpg"

Notes

- Ultralytics `ultralytics` package will download model weights on first run if the named model isn't present. Use a local trained model for production.
- For Windows development you can run the server using PowerShell inside this repository and point the Flutter app to it.
- If you plan to run inside Docker, build the image and run it with a mounted model file.

Troubleshooting / compatibility

- If pip fails to find compatible wheels for packages like numpy or ultralytics, make sure you're using a supported Python version (Python 3.11 is recommended).
- Upgrade pip before installing: `python -m pip install --upgrade pip setuptools wheel`.
- If you see errors like "Could not find a version that satisfies the requirement ultralytics==...", modify `requirements.txt` to use a flexible ultralytics range (the repository already uses `ultralytics>=8.0.0,<9.0.0`).
- On Windows, many binary wheels are published for specific Python versions. If a wheel is unavailable for your Python, either install a matching Python version (3.11), or use a Linux environment / Docker where wheels are available.
- If you prefer not to install ultralytics locally, consider running the detection service in Docker (the Dockerfile is included) on a Linux machine or cloud instance.
