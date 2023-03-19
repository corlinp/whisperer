import json
import queue
import sys
import threading
import time

import numpy as np
import pyaudio
import pyautogui
import whisper
from pynput import keyboard

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

# Load the model
# switch cpu to mps once fixed: https://github.com/pytorch/pytorch/issues/87886
model = whisper.load_model("small.en", device='cpu')

# Enable VAD - detects when you stop speaking and starts transcribing that automatically
use_vad = False

# Global variables
recording = False
audio = pyaudio.PyAudio()
stream = None
frames = []
modifier_pressed = False
modifier_last_pressed = 0
audio_queue = queue.Queue()

# Audio settings
CHUNK = 512
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000

def record_audio():
    """Record audio from the microphone and store it in frames."""
    global recording, stream, frames
    silence_counter = 0
    if not recording:
        recording = True
        stream = audio.open(format=FORMAT,
                            channels=CHANNELS,
                            rate=RATE,
                            input=True,
                            frames_per_buffer=CHUNK)
        frames = []
        print("Recording started...")

    while recording:
        data = stream.read(CHUNK)
        frame = np.frombuffer(data, dtype=np.int16).astype(np.float32, order='C') / 32768.0
        if not use_vad:
            frames.append(frame)
            continue
        # Check if the current frame contains speech
        # definitely need to improve how we do VAD
        avg_volume = np.mean(np.abs(frame))
        is_speech = avg_volume > 0.001
        print(f"Speech: {avg_volume}")
        if is_speech:
            silence_counter = 0
            frames.append(frame)
        else:
            silence_counter += 1

            # Check if silence duration exceeds the threshold
            if silence_counter > 20:  # Adjust this value to change the silence threshold
                silence_counter = 0
                if len(frames) > 0:
                    process_and_clear_frames()
    else:
        stop_recording()

def process_and_clear_frames():
    global frames
    audio_array = np.concatenate(frames)
    audio_queue.put(audio_array)
    frames = []

def stop_recording():
    global recording, stream
    if not recording:
        return
    recording = False
    stream.stop_stream()
    stream.close()
    if len(frames) > 0:
        process_and_clear_frames()

def process_audio():
    """Continuously process audio from the queue and transcribe it."""
    global audio_queue
    while True:
        waveform = audio_queue.get()
        t0 = time.time()
        print("Transcribing audio...")
        try:
            result = model.transcribe(waveform, verbose=False, initial_prompt=prompt, fp16=False)
        except Exception as e:
            print(f"Error: {e}")
            result = model.transcribe(waveform, verbose=False, initial_prompt=prompt, fp16=False)
        # print(json.dumps(result, indent=2))
        transcription = result["text"].strip()
        t1 = time.time()
        transcribe_duration = t1 - t0
        orig_duration = len(waveform) / RATE
        print(f"Audio: {orig_duration:.2f}s, Transcription: {transcribe_duration:.2f}s, Speedup: {orig_duration / transcribe_duration:.2f}x")
        pyautogui.write(transcription + " ")

threading.Thread(target=process_audio).start()

# Hotkey listener
def on_press(key):
    global modifier_last_pressed, recording
    if key == MODIFIER:
        modifier_last_pressed = time.time()
        if recording:
            print("Stopping recording..")
            stop_recording()
        else:
            print("Starting recording..")
            threading.Thread(target=record_audio).start()

def on_release(key):
    global modifier_last_pressed
    if key == MODIFIER:
        if time.time() - modifier_last_pressed < 0.5:
            return
        print("Stopping recording..")
        stop_recording()

if __name__ == "__main__":
    try:
        # Start listening for the hotkey
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            print("Listening for hotkey...")
            listener.join()
    except KeyboardInterrupt:
        print("Exiting...")
        sys.exit(0)