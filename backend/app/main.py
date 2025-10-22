from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Dict, Any
from PIL import Image
import io
import numpy as np
import uvicorn
import base64
import cv2
import tempfile

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


@app.get("/health")
async def health():
    """Returns simple health info including whether the model loaded and class names."""
    loaded = model is not None
    names = list(model.names) if (loaded and hasattr(model, 'names')) else []
    return JSONResponse(content={
        'model_loaded': loaded,
        'model_path': MODEL_PATH,
        'num_classes': len(names),
        'names': names,
    })


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

    # Log detection summary for debugging
    try:
        print(f"[detect] image size={pil.size} boxes={len(boxes_out)} people_count={people_count}")
    except Exception:
        pass

    return JSONResponse(content=resp)


@app.post("/detect_video")
async def detect_video(video: UploadFile = File(...), sample_rate: int = 15, conf: float = 0.25):
    """
    Accepts a video file upload, samples frames at 'sample_rate' (1 frame every sample_rate frames),
    runs YOLO detection on each sampled frame, and returns per-frame detections. The response
    includes optional base64-encoded thumbnails (`image_b64`) for convenience in the frontend.
    """
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    # Save uploaded file to a temporary file because OpenCV needs a path
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        contents = await video.read()
        tmp.write(contents)
        tmp.flush()
        tmp_path = tmp.name
        tmp.close()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to save uploaded video: {e}")

    cap = cv2.VideoCapture(tmp_path)
    if not cap.isOpened():
        raise HTTPException(status_code=400, detail="Unable to open video file")

    frames_out = []
    frame_idx = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % sample_rate != 0:
                frame_idx += 1
                continue

            # convert BGR (cv2) to RGB PIL Image
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            pil = Image.fromarray(rgb)

            # small thumbnail for frontend (resize to max 640 width)
            thumb = pil.copy()
            max_w = 640
            if thumb.width > max_w:
                scale = max_w / float(thumb.width)
                thumb = thumb.resize((int(thumb.width * scale), int(thumb.height * scale)))

            # run detection
            try:
                results = model(pil, imgsz=640, conf=conf, verbose=False)
            except Exception as e:
                cap.release()
                raise HTTPException(status_code=500, detail=f"Detection error: {e}")

            boxes_out: List[Dict[str, Any]] = []
            people_count = 0
            for r in results:
                boxes = getattr(r, 'boxes', None)
                if boxes is None:
                    continue
                for box in boxes:
                    xyxy = box.xyxy.tolist()[0]
                    conf_v = float(box.conf)
                    cls = int(box.cls)
                    name = model.names.get(cls, str(cls)) if hasattr(model, 'names') else str(cls)
                    x1, y1, x2, y2 = xyxy
                    w = x2 - x1
                    h = y2 - y1
                    iw, ih = pil.width, pil.height
                    boxes_out.append({
                        'x': float(x1 / iw),
                        'y': float(y1 / ih),
                        'width': float(w / iw),
                        'height': float(h / ih),
                        'confidence': conf_v,
                        'class_id': cls,
                        'class_name': name,
                    })
                    if name.lower() in ('person', 'people') or cls == 0:
                        people_count += 1

            # encode thumbnail as JPEG base64
            buf = io.BytesIO()
            try:
                thumb.save(buf, format='JPEG', quality=70)
                thumb_b64 = base64.b64encode(buf.getvalue()).decode('ascii')
            except Exception:
                thumb_b64 = None

            frames_out.append({
                'frame_index': frame_idx,
                'people_count': people_count,
                'boxes': boxes_out,
                'image_b64': thumb_b64,
            })

            frame_idx += 1

    finally:
        cap.release()

    return JSONResponse(content={'frames': frames_out})


if __name__ == '__main__':
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
