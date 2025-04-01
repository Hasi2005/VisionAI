import os
import streamlit as st
import google.generativeai as genai
import tempfile
import subprocess
import cv2

# Configure Gemini API
GEMINI_API_KEY = "AIzaSyCvJ9JBjWT6afkrmGoQGB0ZF89yLGTtx_8"  # Replace with your actual API key
genai.configure(api_key=GEMINI_API_KEY)

# Initialize Gemini Model (with Vision Support)
def initialize_model(model_name="gemini-1.5-flash"):
    return genai.GenerativeModel(model_name)

# Extract Frames from Video
def extract_frames(video_path, frame_rate=1):
    cap = cv2.VideoCapture(video_path)
    frames = []
    frame_count = 0
    success, image = cap.read()
    
    while success:
        if frame_count % frame_rate == 0:  # Extract 1 frame every 'frame_rate' frames
            temp_img_path = f"frame_{frame_count}.jpg"
            cv2.imwrite(temp_img_path, image)
            frames.append(temp_img_path)
        
        success, image = cap.read()
        frame_count += 1
    
    cap.release()
    return frames

# Generate AI Response
def get_response(model, prompt, images):
    response = model.generate_content([prompt] + images)
    return response.text

# Streamlit UI
st.title("Video Q&A (No Audio)")
st.markdown("<br>", unsafe_allow_html=True)

# File Upload
uploaded_file = st.file_uploader("Upload an MP4 Video", type=["mp4"])

user_prompt = st.text_area("Ask a question about the video:")
submit = st.button("Submit")

if submit and uploaded_file:
    temp_fd, temp_video_path = tempfile.mkstemp(suffix=".mp4")
    with os.fdopen(temp_fd, "wb") as f:
        f.write(uploaded_file.read())

    # Extract Frames
    frames = extract_frames(temp_video_path, frame_rate=10)  # Extract 1 frame every 10 frames
    
    if not frames:
        st.error("Error: No frames extracted from the video.")
    else:
        # Initialize Gemini Vision Model
        gemini_model = initialize_model()

        # Generate Answer
        model_prompt = f"""You are an expert at analyzing video frames. 
        Given the following images, answer the user's question based only on visual content.

        User Question:
        {user_prompt}
        """

        response = get_response(gemini_model, model_prompt, frames)
        st.write(response)

    # Cleanup
    os.remove(temp_video_path)
    for frame in frames:
        os.remove(frame)
