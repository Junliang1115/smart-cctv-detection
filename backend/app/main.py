from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Dict, Any
from PIL import Image
import io
import numpy as np
import uvicorn

# ultralytics provides YOLOv8 API
from ultralytics import YOLO

app = FastAPI(title="Smart CCTV Detection API")

# Load a YOLOv8 model. By default we use the small 'yolov8n.pt' for speed.
# For production, replace with your trained model path or use a larger backbone.
MODEL_PATH = "yolov8x.pt"

try:
    model = YOLO(MODEL_PATH)
except Exception as e:
    # We'll allow the server to start even if model fails to load; endpoints
    # will return 503 until the model is available.
    model = None
    print(f"Warning: YOLO model failed to load: {e}")

class DetectionBox(BaseModel):
    x: float
    y: float
    width: float
    height: float
    confidence: float
    class_id: int
    class_name: str

class DetectResponse(BaseModel):
    brightness: float
    brightness_category: str
    people_count: int
    boxes: List[DetectionBox]


def _compute_brightness(pil_img: Image.Image) -> float:
    # Convert to grayscale and compute mean (0..255)
    gray = pil_img.convert("L")
    arr = np.array(gray, dtype=np.float32)
    mean = float(np.mean(arr)) / 255.0
    return mean


def _brightness_category(luma: float) -> str:
    if luma < 0.12:
        return "Very dark"
    if luma < 0.40:
        return "Shallow"
    return "Normal"


@app.post("/detect", response_model=DetectResponse)
async def detect(image: UploadFile = File(...)):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    contents = await image.read()
    try:
        pil = Image.open(io.BytesIO(contents)).convert("RGB")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image: {e}")

    # Compute brightness quickly
    brightness = _compute_brightness(pil)
    category = _brightness_category(brightness)

    # Run YOLOv8 detection
    try:
        # Note: results = model(pil) returns list of Results; use .boxes
        results = model(pil, imgsz=640, conf=0.25, verbose=False)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Detection error: {e}")

    boxes_out: List[Dict[str, Any]] = []
    people_count = 0
    # results may be a list of single item
    for r in results:
        boxes = getattr(r, 'boxes', None)
        if boxes is None:
            continue
        for box in boxes:
            # box.xyxy, box.conf, box.cls
            xyxy = box.xyxy.tolist()[0]
            conf = float(box.conf)
            cls = int(box.cls)
            name = model.names.get(cls, str(cls)) if hasattr(model, 'names') else str(cls)
            x1, y1, x2, y2 = xyxy
            w = x2 - x1
            h = y2 - y1
            # Normalize to 0..1 relative to image size
            iw, ih = pil.width, pil.height
            boxes_out.append({
                'x': float(x1 / iw),
                'y': float(y1 / ih),
                'width': float(w / iw),
                'height': float(h / ih),
                'confidence': conf,
                'class_id': cls,
                'class_name': name,
            })
            if name.lower() in ('person', 'people') or cls == 0:
                # YOLO's COCO class 0 is usually 'person'
                people_count += 1

    resp = {
        'brightness': brightness,
        'brightness_category': category,
        'people_count': people_count,
        'boxes': boxes_out,
    }

    return JSONResponse(content=resp)


if __name__ == '__main__':
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
