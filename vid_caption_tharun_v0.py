import cv2
import numpy as np
import torch
from PIL import Image
from transformers import BlipProcessor, BlipForConditionalGeneration

# Load BLIP model and processor
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base").to(device)

# Parameters
THRESHOLD = 0.01  # Scene change detection threshold

# Initialize video capture for live feed (0 is the default camera index)
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("Error: Could not open video capture")
    exit()

prev_hist = None
frame_buffer = []
scene_id = 0

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    # Convert frame to grayscale for scene detection
    gray_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    hist = cv2.calcHist([gray_frame], [0], None, [256], [0, 256])
    hist = cv2.normalize(hist, hist).flatten()

    # Compare histograms to detect scene changes
    if prev_hist is not None:
        diff = cv2.compareHist(prev_hist, hist, cv2.HISTCMP_BHATTACHARYYA)
        if diff > THRESHOLD:  # Scene change detected
            if frame_buffer:
                # Generate caption for the buffered frames
                print(f"Processing Scene {scene_id}")
                # Use the middle frame of the buffer for captioning
                mid_frame = frame_buffer[len(frame_buffer) // 2]
                pil_image = Image.fromarray(cv2.cvtColor(mid_frame, cv2.COLOR_BGR2RGB))

                # Generate caption using BLIP
                inputs = processor(images=pil_image, return_tensors="pt").to(device)
                output = model.generate(**inputs)
                caption = processor.decode(output[0], skip_special_tokens=True)
                print(f"Scene {scene_id} Caption: {caption}")

                # Reset buffer
                frame_buffer = []
                scene_id += 1

    # Update buffer and previous histogram
    frame_buffer.append(frame)
    prev_hist = hist

    # Display live video feed with caption overlay
    if scene_id > 0:
        cv2.putText(frame, caption, (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
    cv2.imshow("Live Feed", frame)

    # Exit on 'q' key press
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()