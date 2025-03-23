import argparse
import base64
import json
import os
import requests
import queue
import sys
import threading
import time

import numpy as np
import pyaudio
import pyautogui
from pynput import keyboard

# Configure your desired hotkey
MODIFIER = keyboard.Key.alt_r

# Add command line argument parsing
parser = argparse.ArgumentParser()
parser.add_argument("--prompt", type=str, help="Initial prompt for transcription")
args = parser.parse_args()

# Update prompt handling
prompt = ""
if args.prompt:
    if args.prompt.endswith(".txt"):
        with open(args.prompt) as f:
            prompt = f.read()
    else:
        prompt = args.prompt
    prompt_preview = prompt[:20] + "..." if len(prompt) > 20 else prompt
    print(f"Using prompt: {prompt_preview}")
else:
    print("No prompt specified")

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

def save_audio_to_wav(frames):
    """Save audio frames to a temporary WAV file."""
    import wave
    temp_wav = "temp_recording.wav"
    with wave.open(temp_wav, 'wb') as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(audio.get_sample_size(FORMAT))
        wf.setframerate(RATE)
        for frame in frames:
            wf.writeframes((frame * 32768).astype(np.int16).tobytes())
    return temp_wav

def transcribe_with_api(audio_file):
    """Transcribe audio using OpenAI's API."""
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not set in environment")

    with open(audio_file, "rb") as f:
        audio_data = f.read()
    
    encoded_audio = base64.b64encode(audio_data).decode('utf-8')
    
    payload = {
        "model": "gpt-4o-audio-preview-2024-12-17",
        "modalities": ["text"],
        # "audio": {"voice": "alloy", "format": "wav"},
        "messages": [{
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": prompt,
                },
                {
                    "type": "input_audio",
                    "input_audio": {
                        "data": encoded_audio,
                        "format": "wav"
                    }
                }
            ]
        }]
    }

    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        },
        json=payload
    )
    
    if response.status_code != 200:
        raise Exception(f"API request failed: {response.text}")
    
    result = response.json()
    return result["choices"][0]["message"]["content"]

def process_audio():
    """Continuously process audio from the queue and transcribe it."""
    global audio_queue
    while True:
        waveform = audio_queue.get()
        t0 = time.time()
        print("Transcribing audio...")
        
        try:
            # Save audio to WAV file for API
            wav_file = save_audio_to_wav(frames)
            transcription = transcribe_with_api(wav_file)
            os.remove(wav_file)  # Clean up temporary file
        except Exception as e:
            print(f"Error: {e}")
            continue

        t1 = time.time()
        transcribe_duration = t1 - t0
        orig_duration = len(waveform) / RATE
        print(f"Audio: {orig_duration:.2f}s, Transcription: {transcribe_duration:.2f}s, Speedup: {orig_duration / transcribe_duration:.2f}x")
        
        transcription = transcription[0].upper() + transcription[1:] + " "
        pyautogui.write(transcription)

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
        # Get the terminal binary path
        terminal_path = os.path.realpath(sys.executable)
        
        # Create the listener without using a context manager
        listener = keyboard.Listener(on_press=on_press, on_release=on_release)
        listener.start()
        
        # Check if the listener actually started
        if not listener.is_alive():
            print("Failed to start listener")
            print("\nIMPORTANT: On macOS, this application requires accessibility permissions.")
            print("Please add this binary to System Settings > Privacy & Security > Accessibility")
            print(f"Binary path: {terminal_path}")
            sys.exit(1)
            
        print("Listening for hotkey...")
        print("Note: If hotkeys aren't working, ensure this binary has both:")
        print("1. Input Monitoring permissions")
        print("2. Accessibility permissions")
        print(f"Binary path: {terminal_path}")
        
        # Keep the main thread running
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("Exiting...")
        listener.stop()
        sys.exit(0)
    except Exception as e:
        print(f"\nERROR: An unexpected error occurred: {e}")
        print("\nIf you're on macOS, please verify both permissions are granted for:")
        print(f"Binary path: {terminal_path}")
        print("\nIn these locations:")
        print("1. System Settings > Privacy & Security > Input Monitoring")
        print("2. System Settings > Privacy & Security > Accessibility")
        sys.exit(1)