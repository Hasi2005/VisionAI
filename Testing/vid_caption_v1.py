import cv2
import numpy as np
from transformers import BlipProcessor, BlipForConditionalGeneration
from skimage.metrics import structural_similarity as ssim
from tqdm import tqdm
import torch

# Load BLIP model and processor
processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base")

def extract_frames_opencv(video_path, fps=1):
    """Extract frames from a video using OpenCV."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video file: {video_path}")
    
    video_fps = int(cap.get(cv2.CAP_PROP_FPS))
    interval = int(video_fps / fps)
    
    frames = []
    frame_count = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_count % interval == 0:
            timestamp = frame_count / video_fps
            frames.append((timestamp, cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)))  # Convert to RGB
        frame_count += 1
    
    cap.release()
    return frames

def group_frames_into_scenes(frames, threshold=50):
    """Group frames into scenes using a basic color histogram difference."""
    scenes = []
    current_scene = [frames[0]]
    
    for i in range(1, len(frames)):
        _, frame1 = frames[i - 1]
        _, frame2 = frames[i]
        # Calculate similarity between consecutive frames
        similarity = ssim(
            frame1.mean(axis=2), frame2.mean(axis=2), data_range=255
        )
        if similarity < threshold / 100:  # Convert threshold to similarity metric
            scenes.append(current_scene)
            current_scene = [frames[i]]
        else:
            current_scene.append(frames[i])
    
    if current_scene:
        scenes.append(current_scene)
    return scenes

def generate_caption(frame):
    """Generate a caption for a single frame."""
    inputs = processor(frame, return_tensors="pt").to("cuda" if torch.cuda.is_available() else "cpu")
    outputs = model.generate(**inputs)
    return processor.decode(outputs[0], skip_special_tokens=True)

def summarize_scene(captions, max_sentences=2):
    """Summarize a list of captions by selecting the first few captions."""
    summary = " ".join(captions[:max_sentences])  # Use the first `max_sentences` captions
    return summary

def process_video(video_path, fps=1):
    """Process the video: caption frames, group into scenes, and summarize."""
    frames = extract_frames_opencv(video_path, fps=fps)
    scenes = group_frames_into_scenes(frames)
    
    results = []
    for scene_index, scene in enumerate(tqdm(scenes, desc="Processing scenes")):
        captions = []
        for timestamp, frame in scene:
            caption = generate_caption(frame)
            captions.append(caption)
        summary = summarize_scene(captions)
        results.append({"scene_index": scene_index, "summary": summary})
    
    return results

if __name__ == "__main__":
    video_file = "VIDEO PATH IN MP4 FORMAT" 
    scene_summaries = process_video(video_file, fps=1)
    for scene in scene_summaries:
        print(f"Scene {scene['scene_index']} Summary: {scene['summary']}")