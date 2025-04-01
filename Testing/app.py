from flask import Flask, request, jsonify
import cv2
import torch
from PIL import Image
import numpy as np
from transformers import AutoProcessor, AutoModelForImageTextToText

app = Flask(__name__)

# Load BLIP model
processor = AutoProcessor.from_pretrained("Salesforce/blip-image-captioning-large")
model = AutoModelForImageTextToText.from_pretrained("Salesforce/blip-image-captioning-large")
device = "cuda" if torch.cuda.is_available() else "cpu"
model.to(device)

def generate_caption(image):
    """Process image and generate caption using BLIP"""
    try:
        # Convert to PIL Image
        pil_image = Image.fromarray(image)

        # Process for model
        inputs = processor(images=pil_image, return_tensors="pt")
        inputs = {k: v.to(device) for k, v in inputs.items()}

        with torch.no_grad():
            output = model.generate(**inputs, max_length=30, num_beams=5, num_return_sequences=1)

        caption = processor.batch_decode(output, skip_special_tokens=True)[0].strip()
        return {"caption": caption}
    except Exception as e:
        return {"error": str(e)}

@app.route("/caption", methods=["POST"])
def caption_image():
    """API endpoint to receive an image and return a caption"""
    try:
        if "image" not in request.files:
            return jsonify({"error": "No image provided"}), 400

        file = request.files["image"]
        image_np = np.frombuffer(file.read(), np.uint8)
        image = cv2.imdecode(image_np, cv2.IMREAD_COLOR)

        response = generate_caption(image)
        return jsonify(response)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)