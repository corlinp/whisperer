import queue
import sys
import threading
import time
from datetime import datetime
import re

import pyaudio
import pyautogui
import pyperclip
from pynput import keyboard
import wave
import subprocess
import numpy as np


# Configure your desired hotkey
MODIFIER = keyboard.Key.alt_r

prompt = ""
if len(sys.argv) > 1:
    prompt = sys.argv[1]
    # if prompt ends in .txt, read the file
    if prompt.endswith(".txt"):
        with open(prompt) as f:
            prompt = f.read()
    prompt_preview = prompt
    if len(prompt_preview) > 20:
        prompt_preview = prompt_preview[:20] + "..."
    print(f"Using prompt: {prompt_preview}")
else:
    print("No prompt specified")

# Global variables
recording = False
audio = pyaudio.PyAudio()
stream = None
frames = []
modifier_pressed = False
modifier_last_pressed = 0
audio_queue = queue.Queue()

recordings_folder = "/Users/corlinpalmer/whispers"
whispercpp_folder = "/Users/corlinpalmer/Documents/GitHub/whisperer/whisper.cpp"

# Audio settings
CHUNK = 512
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000

# models to use based on duration
models = {
    # "tiny.en": (0, 3), # 0 to 3 seconds long
    "base.en": (0, 8),
    "small.en": (8, 99999999),
}
model_duration_cutoff_secs = 8.0


def record_audio(tries=0):
    """Record audio from the microphone and store it in frames."""
    if tries > 3:
        print("Failed to record audio after 3 tries.")
        return

    global recording, stream, frames
    if not recording:
        try:
            stream = audio.open(
                format=FORMAT,
                channels=CHANNELS,
                rate=RATE,
                input=True,
                frames_per_buffer=CHUNK,
            )
            recording = True
            frames = []
            print(
                f"Recording started after {time.time() - modifier_last_pressed:.4f}s."
            )
        except Exception as e:
            print(f"Failed to record audio: {e}")
            return record_audio(tries + 1)

    while recording:
        data = stream.read(CHUNK)
        frames.append(data)
    else:
        stop_recording()


def process_and_clear_frames():
    global frames
    duration = (len(frames) * CHUNK) / RATE

    # Check if recording duration is shorter than 3 seconds
    if duration < 5:
        # Calculate the number of frames to add to each side to pad the recording
        pad_frames = int((5 - duration) * RATE / CHUNK / 2)
        # Create silence frames
        silence_data = np.zeros((CHUNK * pad_frames,), dtype=np.int16).tobytes()
        # Add silence frames to the beginning and end of the recording
        frames.insert(0, silence_data)
        frames.append(silence_data)

    fname = f"{recordings_folder}/recording_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.wav"
    with wave.open(fname, "wb") as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(audio.get_sample_size(FORMAT))
        f.setframerate(RATE)
        f.writeframes(b"".join(frames))

    # Update duration after padding
    duration = (len(frames) * CHUNK) / RATE
    audio_queue.put((fname, duration))
    frames = []


def stop_recording():
    global recording, stream
    stream.stop_stream()
    stream.close()
    if len(frames) > 0:
        process_and_clear_frames()


def process_transcription(s: str):
    # remove any part between [brackets] - this is typically something like [silence] or [buzzing]
    s = re.sub(r"\[.*?\]", "", s)
    s = s.strip().replace("\n", " ").replace("  ", " ")
    if len(s) == 0:
        s = " "
    else:
        s = s[0].upper() + s[1:] + " "
    return s


def process_audio_whispercpp():
    """Continuously process audio from the queue and transcribe it."""
    global audio_queue
    while True:
        fname, orig_duration = audio_queue.get()
        t0 = time.time()
        model = None
        for m, duration_cutoff in models.items():
            if duration_cutoff[0] <= orig_duration <= duration_cutoff[1]:
                model = m
                break
        print(f"Transcribing audio with whispercpp model {model}...")
        cmd = [
            f"{whispercpp_folder}/main",
            "-m",
            f"{whispercpp_folder}/models/ggml-{model}.bin",
            "-f",
            fname,
            "--prompt",
            prompt,
            "-nt",
            "-otxt",
        ]
        result = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        # print stdout and stderr
        print(result.stdout)
        print(result.stderr)
        result.check_returncode()
        output_file = fname + ".txt"
        # read the file
        with open(output_file) as f:
            transcription = f.read()

        t1 = time.time()
        transcribe_duration = t1 - t0
        print(
            f"Audio: {orig_duration:.2f}s, Transcription: {transcribe_duration:.2f}s, Speedup: {orig_duration / transcribe_duration:.2f}x"
        )
        transcription = process_transcription(transcription)
        # pyautogui.write(transcription)
        # instead of write (which is slow and buggy), use pyperclip
        print(f"\n{transcription}\n\n")
        pyperclip.copy(transcription)
        while modifier_pressed:
            time.sleep(0.02)
        time.sleep(0.01)
        # Paste the clipboard content using pyautogui
        pyautogui.keyDown("command")
        pyautogui.press("v")
        pyautogui.keyUp("command")


threading.Thread(target=process_audio_whispercpp).start()


# Hotkey listener
def on_press(key):
    global modifier_last_pressed, recording
    if key == MODIFIER:
        modifier_pressed = True
        modifier_last_pressed = time.time()
        if recording:
            print("Stopping recording..")
            recording = False
        else:
            print("Starting recording..")
            threading.Thread(target=record_audio).start()


def on_release(key):
    global modifier_last_pressed, recording
    if key == MODIFIER:
        modifier_pressed = False
        if time.time() - modifier_last_pressed < 0.25:
            return
        print("Stopping recording..")
        recording = False


if __name__ == "__main__":
    try:
        # Start listening for the hotkey
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            print("Listening for hotkey...")
            listener.join()
    except KeyboardInterrupt:
        print("Exiting...")
        sys.exit(0)
