import os
import streamlit as st
import google.generativeai as genai
from youtube_transcript_api import YouTubeTranscriptApi

# Configure Gemini API
GEMINI_API_KEY = 'AIzaSyCvJ9JBjWT6afkrmGoQGB0ZF89yLGTtx_8'  # Replace with your actual API key
genai.configure(api_key=GEMINI_API_KEY)

# Initialize Gemini Model
def initialize_model(model_name="gemini-1.5-flash"):
    return genai.GenerativeModel(model_name)

# Generate AI Response
def get_response(model, prompt):
    response = model.generate_content(prompt)
    return response.text

# Extract Video Transcripts
def get_video_transcripts(video_id):
    try:
        transcript_list = YouTubeTranscriptApi.get_transcript(video_id)
        return " ".join([t["text"] for t in transcript_list])
    except Exception as e:
        return f"Couldn't transcribe the video: {e}"

# Extract Video ID from URL
def get_video_id(url):
    video_id = url.split("=")[1]
    return video_id.split("&")[0] if "&" in video_id else video_id

# Streamlit App UI
st.title("YouTube Video Summarizer & Q&A")
st.markdown("<br>", unsafe_allow_html=True)

# Input Fields
youtube_url = st.text_input("Enter YouTube Video Link:")
mode = st.radio("Choose Mode:", ["Summarization", "Question Answering"])
user_prompt = st.text_area("Your Question (Only for Q&A Mode)", key="user_prompt", disabled=(mode == "Summarization"))
submit = st.button("Submit")

if submit and youtube_url:
    video_id = get_video_id(youtube_url)
    st.image(f"http://img.youtube.com/vi/{video_id}/0.jpg", use_column_width=True)

    # Fetch Transcription
    transcription = get_video_transcripts(video_id)
    
    if "Couldn't transcribe the video" in transcription:
        st.error("Error: Could not retrieve video transcription.")
    else:
        # Initialize Model
        gemini_model = initialize_model()

        # Generate Summary or Answer
        if mode == "Summarization":
            model_prompt = f"""You are an expert at summarizing YouTube videos from their transcripts. 
            Your task is to provide a concise, informative summary of the given transcription.
            Make the summary clear, structured, and under 1000 words.

            Video Transcription:
            {transcription}
            """
        else:  # Question Answering Mode
            model_prompt = f"""You are an expert at answering questions from YouTube video transcripts.
            Given the transcript and user question, provide a clear and accurate response.
            If the answer is not in the video, say 'The video does not contain relevant information.'

            Video Transcription:
            {transcription}

            User Question:
            {user_prompt}
            """

        # Generate AI Response
        response = get_response(gemini_model, model_prompt)
        st.write(response)
