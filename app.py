#doesnt work with the python 3.13 version for some reason 
#venv_312\Scripts\activate

import cv2
from transformers import AutoProcessor, AutoModelForImageTextToText
import torch
import logging
import time
from PIL import Image
import sys
from threading import Thread, Lock
from queue import Queue
import base64
import io
import numpy as np
from flask import Flask, jsonify, request, Response
import json
from flask_cors import CORS
import socket
import os
from aiohttp import web
from aiortc import RTCPeerConnection, RTCSessionDescription
from aiortc.contrib.media import MediaStreamTrack
from av import VideoFrame
import asyncio

# Logging setup
def setup_logging():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
    return logging.getLogger(__name__)

logger = setup_logging()

# Caption Generator
class CaptionGenerator:
    def __init__(self, processor, model, device):
        self.processor = processor
        self.model = model
        self.device = device
        self.current_caption = f"Initializing caption... ({device.upper()})"
        self.caption_queue = Queue(maxsize=1)
        self.lock = Lock()
        self.running = True
        self.thread = Thread(target=self._caption_worker)
        self.thread.daemon = True
        self.thread.start()

    def _caption_worker(self):
        while self.running:
            try:
                if not self.caption_queue.empty():
                    frame = self.caption_queue.get()
                    caption = self._generate_caption(frame)
                    with self.lock:
                        self.current_caption = caption
            except Exception as e:
                logging.error(f"Caption worker error: {str(e)}")
            time.sleep(0.1)

    def _generate_caption(self, image):
        try:
            image_resized = cv2.resize(image, (640, 480))
            rgb_image = cv2.cvtColor(image_resized, cv2.COLOR_BGR2RGB)
            pil_image = Image.fromarray(rgb_image)

            inputs = self.processor(images=pil_image, return_tensors="pt")
            inputs = {name: tensor.to(self.device) for name, tensor in inputs.items()}

            with torch.no_grad():
                outputs = self.model.generate(**inputs, max_length=30, num_beams=5, num_return_sequences=1)

            caption = self.processor.batch_decode(outputs, skip_special_tokens=True)[0].strip()
            return f"BLIP: {caption} ({self.device.upper()})"
        except Exception as e:
            logging.error(f"Caption generation error: {str(e)}")
            return f"BLIP: Caption generation failed ({self.device.upper()})"

    def update_frame(self, frame):
        if self.caption_queue.empty():
            try:
                self.caption_queue.put_nowait(frame.copy())
            except:
                pass

    def get_caption(self):
        with self.lock:
            return self.current_caption

    def stop(self):
        self.running = False
        if self.thread.is_alive():
            self.thread.join(timeout=1.0)

# Get GPU usage
def get_gpu_usage():
    if torch.cuda.is_available():
        memory_allocated = torch.cuda.memory_allocated() / (1024 ** 2)
        memory_total = torch.cuda.get_device_properties(0).total_memory / (1024 ** 2)
        memory_used_percent = (memory_allocated / memory_total) * 100
        return f"GPU Memory Usage: {memory_used_percent:.2f}% | Allocated: {memory_allocated:.2f} MB / {memory_total:.2f} MB"
    else:
        return "GPU not available"

# Get local IP
def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "Could not determine IP"

# Load models
def load_models():
    try:
        blip_processor = AutoProcessor.from_pretrained("Salesforce/blip-image-captioning-large")
        blip_model = AutoModelForImageTextToText.from_pretrained("Salesforce/blip-image-captioning-large")

        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        if device == 'cuda':
            torch.cuda.set_per_process_memory_fraction(0.9)
            blip_model = blip_model.to('cuda')

        return blip_processor, blip_model, device
    except Exception as e:
        logging.error(f"Failed to load models: {str(e)}")
        return None, None, None

# Global variables
caption_generator = None
peer_connections = set()

# Custom WebRTC video track that processes frames with captions
class CaptioningVideoStreamTrack(MediaStreamTrack):
    kind = "video"

    def __init__(self, track):
        super().__init__()
        self.track = track
        self.last_caption_time = time.time()
        self.caption = "Initializing..."
        self.frames_processed = 0

    async def recv(self):
        global caption_generator
        frame = await self.track.recv()
        self.frames_processed += 1

        if caption_generator and self.frames_processed % 15 == 0:
            img = frame.to_ndarray(format="bgr24")
            caption_generator.update_frame(img)
            self.caption = caption_generator.get_caption()

        frame.caption = self.caption
        return frame

# Initialize Flask app
app = Flask(__name__)
CORS(app)

# Initialize caption generator
def init_caption_generator():
    global caption_generator
    logger.info("Loading BLIP model...")
    blip_processor, blip_model, device = load_models()
    if None in (blip_processor, blip_model):
        logger.error("Failed to load the BLIP model.")
        return False

    logger.info(f"Using {device.upper()} for inference.")
    caption_generator = CaptionGenerator(blip_processor, blip_model, device)
    return True

# Flask routes
@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'ok', 'mode': 'WebRTC streaming with captioning'})

@app.route('/api/caption', methods=['GET'])
def get_caption():
    global caption_generator
    if caption_generator:
        return jsonify({'caption': caption_generator.get_caption(), 'timestamp': time.time()})
    else:
        return jsonify({'caption': 'Captioning not available', 'timestamp': time.time()})

# WebRTC handling
async def offer(request):
    global peer_connections
    params = await request.json()
    offer = RTCSessionDescription(sdp=params["sdp"], type=params["type"])

    pc = RTCPeerConnection()
    peer_connections.add(pc)

    @pc.on("icecandidate")
    async def on_icecandidate(candidate):
        if candidate:
            await request.app["queue"].put(json.dumps({"candidate": candidate.to_dict()}))

    @pc.on("track")
    async def on_track(track):
        logger.info(f"Track received: {track.kind}")

        if track.kind == "video":
            captioned_track = CaptioningVideoStreamTrack(track)
            pc.addTrack(captioned_track)

        @track.on("ended")
        async def on_ended():
            logger.info(f"Track {track.kind} ended.")
            peer_connections.discard(pc)

    await pc.setRemoteDescription(offer)
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)

    return web.json_response({"sdp": pc.localDescription.sdp, "type": pc.localDescription.type})

# Initialize WebRTC
async def handle_webrtc():
    app_webrtc = web.Application()
    app_webrtc.router.add_post("/webrtc/offer", offer)
    return app_webrtc

# Run Flask app
if __name__ == "__main__":
    if not init_caption_generator():
        logger.error("Exiting due to model load failure.")
        sys.exit(1)

    ip_address = get_local_ip()
    logger.info(f"Server running on: http://{ip_address}:5000")
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)
