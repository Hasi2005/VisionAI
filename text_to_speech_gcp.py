import cv2
from transformers import AutoProcessor, AutoModelForImageTextToText
import torch
import logging
import time
from PIL import Image
import sys
from threading import Thread, Lock
from queue import Queue
import io
import sounddevice as sd
import numpy as np
from pydub import AudioSegment
from google.cloud import texttospeech
import pygame
import os

def setup_logging():
    """Configure logging with basic formatting"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    return logging.getLogger(__name__)

logger = setup_logging()

# Set Google Cloud credentials path
os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = r"C:\Users\saiak\Desktop\Vision_AI\boxwood-yen-449809-h1-fdb6275186f5.json"


# Fix 1: Import Queue and Empty properly
from queue import Queue, Empty  # Changed import

class GoogleTTSService:
    def __init__(self):
        self.audio_queue = Queue(maxsize=2)
        self.lock = Lock()
        self.running = True
        self.client = texttospeech.TextToSpeechClient()
        self.thread = Thread(target=self._tts_worker)
        self.thread.daemon = True
        self.thread.start()
        self.currently_playing = False 

    def _tts_worker(self):
        while self.running:
            try:
                text = self.audio_queue.get(timeout=0.1)
                self._generate_and_play(text)
            except Empty:  
                continue
            except Exception as e:
                logger.error(f"TTS Error: {str(e)}")

    def _generate_and_play(self, text):
        try:
            # Generate speech
            synthesis_input = texttospeech.SynthesisInput(text=text)
            voice = texttospeech.VoiceSelectionParams(
                language_code="en-US",
                name="en-US-Studio-O",
                ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,  # Changed to MP3
                speaking_rate=1.15
            )

            response = self.client.synthesize_speech(
                input=synthesis_input,
                voice=voice,
                audio_config=audio_config
            )

            # Fix 2: Use pygame for more reliable audio playback
            pygame.mixer.init()
            audio_data = io.BytesIO(response.audio_content)
            pygame.mixer.music.load(audio_data)
            pygame.mixer.music.play()
            
            # Wait for audio to finish playing
            while pygame.mixer.music.get_busy():
                pygame.time.Clock().tick(10)

        except Exception as e:
            logger.error(f"Speech synthesis failed: {str(e)}")

    def add_text(self, text):
        if self.audio_queue.qsize() < 2:
            self.audio_queue.put(text)

    def stop(self):
        self.running = False
        self.thread.join()

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
        self.tts = GoogleTTSService()

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
            time.sleep(0.1)  # Prevent busy waiting

    def _generate_caption(self, image):
        try:
            image_resized = cv2.resize(image, (640, 480))
            rgb_image = cv2.cvtColor(image_resized, cv2.COLOR_BGR2RGB)
            pil_image = Image.fromarray(rgb_image)

            inputs = self.processor(images=pil_image, return_tensors="pt")
            inputs = {name: tensor.to(self.device) for name, tensor in inputs.items()}

            with torch.no_grad():
                outputs = self.model.generate(
                    **inputs,
                    max_length=30,
                    num_beams=5,
                    num_return_sequences=1
                )

            caption = self.processor.batch_decode(outputs, skip_special_tokens=True)[0].strip()
            full_caption = f"BLIP: {caption} ({self.device.upper()})"
            self.tts.add_text(caption)  # Send to TTS for audio playback
            return full_caption

        except Exception as e:
            logging.error(f"Caption generation error: {str(e)}")
            return f"BLIP: Caption generation failed ({self.device.upper()})"

    def update_frame(self, frame):
        if self.caption_queue.empty():
            try:
                self.caption_queue.put_nowait(frame.copy())
            except:
                pass  # Queue is full, skip this frame

    def get_caption(self):
        with self.lock:
            return self.current_caption

    def stop(self):
        self.running = False
        self.thread.join()
        self.tts.stop()

def get_gpu_usage():
    """Get the GPU memory usage and approximate utilization"""
    if torch.cuda.is_available():
        memory_allocated = torch.cuda.memory_allocated() / (1024 ** 2)  # MB
        memory_total = torch.cuda.get_device_properties(0).total_memory / (1024 ** 2)  # MB

        memory_used_percent = (memory_allocated / memory_total) * 100
        gpu_info = f"GPU Memory Usage: {memory_used_percent:.2f}% | Allocated: {memory_allocated:.2f} MB / {memory_total:.2f} MB"
        
        return gpu_info
    else:
        return "GPU not available"

def load_models():
    """Load BLIP model"""
    try:
        blip_processor = AutoProcessor.from_pretrained("Salesforce/blip-image-captioning-large")
        blip_model = AutoModelForImageTextToText.from_pretrained("Salesforce/blip-image-captioning-large")

        device = 'cuda' if torch.cuda.is_available() else 'cpu'
        if device == 'cuda':
            torch.cuda.set_per_process_memory_fraction(0.9)
            blip_model.to('cuda')

        return blip_processor, blip_model, device

    except Exception as e:
        logging.error(f"Failed to load models: {str(e)}")
        return None, None, None

def live_stream_with_caption(processor, model, device, display_width=640, display_height=480):
    """Stream webcam feed with live captions and FPS"""
    cap = cv2.VideoCapture(1)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        logger.error("Failed to access webcam.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, display_width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, display_height)

    logger.info(f"Webcam feed started successfully using {device.upper()}.")
    caption_generator = CaptionGenerator(processor, model, device)

    prev_time = time.time()  # Track time to calculate FPS

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                logger.error("Failed to read frame from webcam.")
                break

            caption_generator.update_frame(frame)
            current_caption = caption_generator.get_caption()

            gpu_info = get_gpu_usage()

            curr_time = time.time()
            fps = 1 / (curr_time - prev_time)
            prev_time = curr_time

            max_width = 40
            caption_lines = [current_caption[i:i + max_width] for i in range(0, len(current_caption), max_width)]

            y_offset = 40
            for line in caption_lines:
                cv2.putText(frame, line, (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                y_offset += 30

            cv2.putText(frame, gpu_info, (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 1)
            y_offset += 30
            cv2.putText(frame, f"FPS: {fps:.2f}", (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 1)

            cv2.imshow("BLIP: Unified Vision-Language Captioning", frame)

            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    except KeyboardInterrupt:
        logger.info("Stream interrupted by user.")
    
    finally:
        caption_generator.stop()
        cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    logger.info("Loading BLIP model...")
    blip_processor, blip_model, device = load_models()
    
    if None in (blip_processor, blip_model):
        logging.error("Failed to load the BLIP model. Exiting.")
        sys.exit(1)

    logger.info(f"Using {device.upper()} for inference.")
    logger.info("Starting live stream with BLIP captioning and FPS display...")
    
    live_stream_with_caption(blip_processor, blip_model, device)
