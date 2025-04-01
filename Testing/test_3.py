import requests

url = "http://127.0.0.1:5000/caption"
image_path = "download.jpg"

with open(image_path, "rb") as img:
    response = requests.post(url, files={"image": img})

print(response.json())