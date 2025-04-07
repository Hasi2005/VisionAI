from gtts import gTTS
from io import BytesIO
import pygame

def speak(text, lang='en'):
    # Convert text to speech in memory
    tts = gTTS(text=text, lang=lang)
    fp = BytesIO()
    tts.write_to_fp(fp)
    fp.seek(0)

    # Initialize pygame mixer
    pygame.mixer.init()
    pygame.mixer.music.load(fp, 'mp3')
    pygame.mixer.music.play()

    # Wait until audio is done
    while pygame.mixer.music.get_busy():
        continue

if __name__ == "__main__":
    user_input = input("Enter text to speak: ")
    speak(user_input)
