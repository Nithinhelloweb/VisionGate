# Face Recognition Module
# Extracted from main.py for better organization

import os
import sys
import threading
import numpy as np
import cv2
import hashlib
from datetime import datetime
from typing import Optional, Tuple, List, Dict, Any

_face_app_lock = threading.Lock()

try:
    import torch
    torch_available = True
    # Try to add torch/lib DLLs to path for ONNX Runtime GPU support on Windows
    if hasattr(os, "add_dll_directory"):
        torch_lib = os.path.join(os.path.dirname(torch.__file__), "lib")
        if os.path.exists(torch_lib):
            try:
                os.add_dll_directory(torch_lib)
                print(f"Added Torch DLL directory to path: {torch_lib}")
            except Exception as e:
                print(f"Note: Could not add Torch DLL directory to path: {e}")
except ImportError:
    torch_available = False

try:
    from insightface.app import FaceAnalysis
    insightface_available = True
except ImportError:
    insightface_available = False

from .cache import _face_profile_cache

# Configuration constants
CONFIDENCE_THRESHOLD = 0.60
MIN_COSINE_SIMILARITY = 0.50
MAX_EUCLIDEAN_DISTANCE = 1.2
INSIGHTFACE_BASE_THRESHOLD = 0.68
FALLBACK_BASE_THRESHOLD = 0.95
INSIGHTFACE_NEAR_MATCH_MARGIN = 0.060
MAX_PROFILE_SAMPLES = 24
PROFILE_SAMPLE_MIN_CONFIDENCE = 0.78

# Global variables
face_app = None
use_fallback = False
face_cascade = None
face_cascade_alt = None
face_cascade_profile = None
extract_face_recursion_depth = 0

def initialize_face_recognition():
    """Initialize face recognition system."""
    global face_app, use_fallback, face_cascade

    if not insightface_available:
        print("InsightFace not available - using fallback mode")
        use_fallback = True
        return

    try:
        print("Trying InsightFace buffalo_s...")
        if torch_available:
            gpu_available = torch.cuda.is_available()
            if gpu_available:
                try:
                    import onnxruntime as ort
                    available_providers = ort.get_available_providers()
                    if "CUDAExecutionProvider" in available_providers:
                        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
                        ctx_id = 0
                        print("GPU available, using GPU for face analysis")
                    else:
                        gpu_available = False
                        providers = ["CPUExecutionProvider"]
                        ctx_id = -1
                        print("ONNX Runtime: CUDAExecutionProvider not available in package. Using CPU.")
                except Exception as e:
                    gpu_available = False
                    providers = ["CPUExecutionProvider"]
                    ctx_id = -1
                    print(f"ONNX Runtime check failed ({e}). Using CPU.")
            else:
                providers = ["CPUExecutionProvider"]
                ctx_id = -1
                print("GPU not available, using CPU for face analysis")
        else:
            gpu_available = False
            providers = ["CPUExecutionProvider"]
            ctx_id = -1
            print("PyTorch not available, using CPU for face analysis")

        face_app = FaceAnalysis(name="buffalo_s", providers=providers)
        face_app.prepare(ctx_id=ctx_id, det_size=(640, 640))

        # Warm up the model
        try:
            dummy_img = np.zeros((640, 640, 3), dtype=np.uint8)
            face_app.get(dummy_img)
            print("Face recognition model warmed up successfully")
        except Exception as e:
            print(f"Model warm-up failed (non-critical): {e}")

        print("InsightFace initialized successfully!")
        use_fallback = False

    except Exception as e:
        print(f"InsightFace failed: {e}")
        print("🔄 Using fallback face recognition system")
        use_fallback = True

    # Log which face recognition mode is active
    if use_fallback:
        print("=" * 60)
        print("⚠️  WARNING: Using FALLBACK face recognition!")
        print("⚠️  This is UNSECURE - ANY face may match ANY other face!")
        print("=" * 60)
    else:
        print("=" * 60)
        print("Using INSIGHTFACE for face recognition!")
        print("=" * 60)

def get_insightface_app():
    """
    Returns the global InsightFace FaceAnalysis application instance if loaded and active.
    Returns None if InsightFace is unavailable or fallback mode is active.
    """
    global face_app, use_fallback
    if not use_fallback and face_app is not None:
        return face_app
    return None

def create_fallback_embedding(face_img):
    """Create a simple but reliable fallback embedding"""
    try:
        face_resized = cv2.resize(face_img, (128, 128))
        gray = cv2.cvtColor(face_resized, cv2.COLOR_BGR2GRAY)

        features = []
        for i in range(0, 128, 32):
            for j in range(0, 128, 32):
                region = gray[i : i + 32, j : j + 32]
                features.append(np.mean(region))
                features.append(np.std(region))
                features.append(np.max(region))
                features.append(np.min(region))

        features.append(np.mean(gray))
        features.append(np.std(gray))
        features.append(np.max(gray))
        features.append(np.min(gray))

        face_hash = hashlib.sha256(gray.tobytes()).hexdigest()
        for i in range(0, len(face_hash), 4):
            hex_val = face_hash[i : i + 4]
            if len(hex_val) == 4:
                features.append(int(hex_val, 16) / 65535.0)

        embedding = np.array(features, dtype=np.float32)

        target_size = 512
        if len(embedding) < target_size:
            embedding = np.pad(embedding, (0, target_size - len(embedding)), "constant")
        elif len(embedding) > target_size:
            embedding = embedding[:target_size]

        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm

        return embedding

    except Exception as e:
        print(f"Fallback embedding error: {e}")
        np.random.seed(int(datetime.now().timestamp() * 1000))
        return np.random.rand(512).astype(np.float32)

def calculate_similarity(embedding1, embedding2):
    """Calculate robust similarity between two embeddings"""
    try:
        cosine_sim = np.dot(embedding1, embedding2) / (
            np.linalg.norm(embedding1) * np.linalg.norm(embedding2)
        )

        euclidean_dist = np.linalg.norm(embedding1 - embedding2)
        euclidean_sim = 1 / (1 + euclidean_dist)

        manhattan_dist = np.sum(np.abs(embedding1 - embedding2))
        manhattan_sim = 1 / (1 + manhattan_dist)

        corr = (
            np.corrcoef(embedding1, embedding2)[0, 1]
            if np.std(embedding1) > 0 and np.std(embedding2) > 0
            else 0
        )

        combined_sim = (
            0.5 * cosine_sim
            + 0.2 * euclidean_sim
            + 0.15 * manhattan_sim
            + 0.15 * max(0, corr)
        )

        return combined_sim, cosine_sim, euclidean_dist, manhattan_dist, corr

    except Exception as e:
        print(f"Similarity calculation error: {e}")
        return 0.0, 0.0, float("inf"), 0.0, 0.0

def preprocess_image_data(img_np_or_bytes):
    """Preprocess image data for face recognition"""
    if isinstance(img_np_or_bytes, bytes):
        nparr = np.frombuffer(img_np_or_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    else:
        img = img_np_or_bytes

    if img is None:
        raise ValueError("Invalid image data")

    # Fix front-camera mirroring
    img = cv2.flip(img, 1)

    h, w, _ = img.shape
    max_size = 1024
    if max(h, w) > max_size:
        scale = max_size / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)))

    # Gamma Correction
    gamma = 1.2
    invGamma = 1.0 / gamma
    table = np.array(
        [((i / 255.0) ** invGamma) * 255 for i in np.arange(0, 256)]
    ).astype("uint8")
    img = cv2.LUT(img, table)

    return img

def extract_face(img, _recursion_depth=0):
    """Extract face from image with multi-angle rotation, selfie-flip fallback, and thread locking."""
    global use_fallback, face_app, face_cascade, _face_app_lock

    if img is None or not hasattr(img, "shape") or img.size == 0:
        return None

    if _recursion_depth > 2:
        return None

    if not use_fallback and face_app is not None:
        try:
            # 1. Direct detection on original image
            with _face_app_lock:
                faces = face_app.get(img)
            if faces and len(faces) > 0:
                best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                if best_face.embedding is not None and len(best_face.embedding) > 0:
                    return best_face

            # 2. Flipped horizontal (front/selfie camera mirroring)
            flipped = cv2.flip(img, 1)
            with _face_app_lock:
                faces = face_app.get(flipped)
            if faces and len(faces) > 0:
                best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                if best_face.embedding is not None and len(best_face.embedding) > 0:
                    return best_face

            # 3. 90 deg clockwise (phone portrait orientation)
            rot90 = cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
            with _face_app_lock:
                faces = face_app.get(rot90)
            if faces and len(faces) > 0:
                best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                if best_face.embedding is not None and len(best_face.embedding) > 0:
                    return best_face

            # 4. 90 deg counter-clockwise (270 deg)
            rot270 = cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
            with _face_app_lock:
                faces = face_app.get(rot270)
            if faces and len(faces) > 0:
                best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                if best_face.embedding is not None and len(best_face.embedding) > 0:
                    return best_face

            # 5. 180 deg upside-down
            rot180 = cv2.rotate(img, cv2.ROTATE_180)
            with _face_app_lock:
                faces = face_app.get(rot180)
            if faces and len(faces) > 0:
                best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                if best_face.embedding is not None and len(best_face.embedding) > 0:
                    return best_face

            # 6. Contrast-enhanced CLAHE fallback (for low-light/harsh backlighting)
            try:
                lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
                l_channel, a, b = cv2.split(lab)
                clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
                cl = clahe.apply(l_channel)
                enhanced = cv2.cvtColor(cv2.merge((cl, a, b)), cv2.COLOR_LAB2BGR)
                with _face_app_lock:
                    faces = face_app.get(enhanced)
                if faces and len(faces) > 0:
                    best_face = max(faces, key=lambda f: getattr(f, "det_score", 0.0) or (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                    if best_face.embedding is not None and len(best_face.embedding) > 0:
                        return best_face
            except Exception:
                pass

        except Exception as e:
            print(f"InsightFace extraction note: {e}")

    # Fallback to OpenCV Haar Cascade detection if InsightFace misses or fallback mode is on
    if face_cascade is None:
        try:
            face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
        except Exception:
            pass

    if face_cascade is not None:
        try:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img
            all_faces = []
            faces1 = face_cascade.detectMultiScale(gray, 1.1, 3, minSize=(30, 30))
            if len(faces1) > 0:
                all_faces.extend(faces1)
            else:
                faces2 = face_cascade.detectMultiScale(cv2.flip(gray, 1), 1.1, 3, minSize=(30, 30))
                if len(faces2) > 0:
                    all_faces.extend(faces2)

            if len(all_faces) > 0:
                x, y, w, h = max(all_faces, key=lambda f: f[2] * f[3])
                face_img = img[y:y+h, x:x+w]
                embedding = create_fallback_embedding(face_img)

                class MockFace:
                    def __init__(self, embedding, bbox):
                        self.embedding = embedding
                        self.bbox = bbox
                        self.det_score = 0.92

                return MockFace(embedding, [x, y, x+w, y+h])
        except Exception as cascade_err:
            print(f"Haar cascade detection note: {cascade_err}")

    # As a last-resort fallback when image is valid, use center crop fallback embedding
    try:
        h, w = img.shape[:2]
        crop_h, crop_w = int(h * 0.7), int(w * 0.7)
        start_y, start_x = (h - crop_h) // 2, (w - crop_w) // 2
        center_crop = img[start_y:start_y+crop_h, start_x:start_x+crop_w]
        embedding = create_fallback_embedding(center_crop)

        class CenterCropMockFace:
            def __init__(self, embedding, bbox):
                self.embedding = embedding
                self.bbox = bbox
                self.det_score = 0.85

        return CenterCropMockFace(embedding, [start_x, start_y, start_x+crop_w, start_y+crop_h])
    except Exception:
        return None

def verify_face_identity(reg_no: str, query_embedding: np.ndarray) -> Tuple[bool, float, str]:
    """Verify if the query face matches the enrolled identity for the given reg_no."""
    profile = _face_profile_cache.get(reg_no)
    if profile is None:
        return False, 0.0, f"User {reg_no} not found"

    if profile["primary"] is None:
        return False, 0.0, f"No face data enrolled for {reg_no}"

    query_embedding = _normalize_embedding(query_embedding)
    if query_embedding is None:
        return False, 0.0, "Invalid query embedding"

    candidates = _get_candidates(reg_no)
    if not candidates:
        return False, 0.0, "No valid profile embeddings available"

    valid_candidates = [c for c in candidates if len(c) == len(query_embedding)]
    if not valid_candidates:
        return False, 0.0, "Embedding dimension mismatch"

    cand_matrix = np.asarray(valid_candidates)
    sims = np.dot(cand_matrix, query_embedding)
    best_index = int(np.argmax(sims))
    best_similarity = float(sims[best_index])

    if use_fallback:
        threshold = FALLBACK_BASE_THRESHOLD
    else:
        threshold = (
            INSIGHTFACE_BASE_THRESHOLD
            if len(candidates) > 1
            else max(INSIGHTFACE_BASE_THRESHOLD, 0.70)
        )

    print(f"DEBUG: Verification for {reg_no}")
    print(f"  Candidates: {len(candidates)}")
    print(f"  Best cosine similarity: {best_similarity:.4f} (candidate #{best_index + 1})")
    print(f"  Threshold: {threshold:.4f}, fallback={use_fallback}")

    if best_similarity >= threshold:
        return True, best_similarity, "Face verified successfully"

    if not use_fallback and best_similarity >= (threshold - INSIGHTFACE_NEAR_MATCH_MARGIN):
        print(f"  Near-match accepted: {best_similarity:.4f} within margin {INSIGHTFACE_NEAR_MATCH_MARGIN:.4f}")
        return True, best_similarity, "Face verified successfully (near-match)"

    reason = "Face does not match - Please try again"
    return False, 0.0, reason

def _normalize_embedding(embedding: np.ndarray):
    """Return unit-normalized embedding or None if invalid."""
    try:
        norm = np.linalg.norm(embedding)
        if norm > 0:
            return embedding / norm
        return None
    except:
        return None

def _get_candidates(reg_no: str):
    """Get all candidate embeddings for a user from cache."""
    profile = _face_profile_cache.get(reg_no)
    if profile is None:
        return []

    candidates = []
    if profile["primary"] is not None:
        candidates.append(profile["primary"])

    for sample in profile.get("samples", []):
        candidates.append(sample)

    # Deduplicate
    unique = []
    seen = set()
    for emb in candidates:
        key = emb.tobytes()
        if key not in seen:
            seen.add(key)
            unique.append(emb)
    return unique