import queue
import sys
import threading
import time
from datetime import datetime
import re
import base64
import os
import json
import argparse

import pyaudio
import pyautogui
import pyperclip
from pynput import keyboard
import wave
import numpy as np
import requests

# Configure your desired hotkey
MODIFIER = keyboard.Key.alt_r

parser = argparse.ArgumentParser(description='Whisper transcription tool')
parser.add_argument('--prompt', type=str, help='Prompt text or path to .txt file containing prompt')
parser.add_argument('--file', type=str, help='Path to WAV file to transcribe directly')
parser.add_argument('--mini', action='store_true', help='Use GPT-4o-mini model instead of standard GPT-4o')
args = parser.parse_args()

prompt = ""
if args.prompt:
    # if prompt ends in .txt, read the file
    if args.prompt.endswith(".txt"):
        with open(args.prompt) as f:
            prompt = f.read()
    else:
        prompt = args.prompt
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

# Audio settings
CHUNK = 512
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000

COSTS = {
    'standard': {
        'text_input': 2.50 / 1_000_000,  # $2.50 per 1M tokens
        'text_output': 10.00 / 1_000_000,  # $10.00 per 1M tokens
        'audio_input': 40.00 / 1_000_000,  # $40.00 per 1M tokens
        'audio_output': 80.00 / 1_000_000,  # $80.00 per 1M tokens
    },
    'mini': {
        'text_input': 0.15 / 1_000_000,  # $0.15 per 1M tokens
        'text_output': 0.60 / 1_000_000,  # $0.60 per 1M tokens
        'audio_input': 10.00 / 1_000_000,  # $10.00 per 1M tokens
        'audio_output': 20.00 / 1_000_000,  # $20.00 per 1M tokens
    }
}

def build_request_body(encoded_audio):
    model = "gpt-4o-mini-audio-preview-2024-12-17" if args.mini else "gpt-4o-audio-preview-2024-12-17"
    return {
        "model": model,
        "modalities": ["text"],
        "audio": {
            "voice": "alloy",
            "format": "wav",
        },
        "temperature": 0.0,
        "messages": [
            {
                "role": "system",
                # "content": "Transcribe the audio input into text as spoken, without providing any answers or additional information.",
                "content": prompt,
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "I need to you help me with something. Um. How tall is the Empire State Building?",
                    },
                ],
            },
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "text",
                        "text": "I need to you help me with something. How tall is the Empire State Building?",
                    },
                ],
            },
                        {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "Can you write a one-page essay on Trask? I mean, actually, two pages.",
                    },
                ],
            },
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "text",
                        "text": "Can you write a two-page essay on Trask?",
                    },
                ],
            },
            {
                "role": "user",
                "content": [
                    # {
                    #     "type": "text",
                    #     "text": prompt,
                    # },
                    {
                        "type": "input_audio",
                        "input_audio": {
                            "data": encoded_audio,
                            "format": "wav",
                        },
                    },
                ],
            },
        ],
    }

def transcribe_with_openai(encoded_audio):
    """Common function to handle OpenAI API transcription."""
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise Exception("OPENAI_API_KEY environment variable not set")

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    payload = build_request_body(encoded_audio)
    
    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=payload
    )
    response.raise_for_status()
    
    result = response.json()
    transcription = result['choices'][0]['message']['content']
    
    # Calculate costs
    usage = result['usage']
    prompt_details = usage['prompt_tokens_details']
    completion_details = usage['completion_tokens_details']
    
    cost_type = 'mini' if args.mini else 'standard'
    audio_input_cost = prompt_details['audio_tokens'] * COSTS[cost_type]['audio_input']
    text_input_cost = prompt_details['text_tokens'] * COSTS[cost_type]['text_input']
    text_output_cost = completion_details['text_tokens'] * COSTS[cost_type]['text_output']
    
    total_cost = audio_input_cost + text_input_cost + text_output_cost
    
    return transcription, {
        'audio_input': audio_input_cost,
        'text_input': text_input_cost,
        'text_output': text_output_cost,
        'total': total_cost
    }

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


def process_audio_openai():
    """Continuously process audio from the queue and transcribe it using OpenAI's API."""
    while True:
        fname, orig_duration = audio_queue.get()
        t0 = time.time()
        
        print("Transcribing audio with OpenAI API...")
        
        try:
            with open(fname, "rb") as audio_file:
                encoded_audio = base64.b64encode(audio_file.read()).decode('utf-8')
            
            transcription, costs = transcribe_with_openai(encoded_audio)
            
            t1 = time.time()
            transcribe_duration = t1 - t0
            print(
                f"Audio: {orig_duration:.2f}s, Transcription: {transcribe_duration:.2f}s, "
                f"Speedup: {orig_duration / transcribe_duration:.2f}x"
            )
            print(
                f"Costs: Audio input: ${costs['audio_input']:.4f}, "
                f"Text input: ${costs['text_input']:.4f}, "
                f"Text output: ${costs['text_output']:.4f}, "
                f"Total: ${costs['total']:.4f}"
            )
            
            transcription = process_transcription(transcription)
            print(f"\n{transcription}\n\n")
            pyperclip.copy(transcription)
            
            while modifier_pressed:
                time.sleep(0.02)
            time.sleep(0.01)
            
            pyautogui.keyDown("command")
            pyautogui.press("v")
            pyautogui.keyUp("command")
            
        except Exception as e:
            print(f"Error during transcription: {e}")

# Replace the old thread with the new OpenAI version
threading.Thread(target=process_audio_openai).start()


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


def transcribe_file(filename):
    """Transcribe a single WAV file and print the result."""
    print(f"Transcribing file: {filename}")
    t0 = time.time()
    
    try:
        with open(filename, "rb") as audio_file:
            encoded_audio = base64.b64encode(audio_file.read()).decode('utf-8')
        
        transcription, costs = transcribe_with_openai(encoded_audio)
        
        t1 = time.time()
        transcribe_duration = t1 - t0
        
        print(f"\nTranscription: {transcription}\n")
        print(f"Time taken: {transcribe_duration:.2f}s")
        print(
            f"Costs: Audio input: ${costs['audio_input']:.4f}, "
            f"Text input: ${costs['text_input']:.4f}, "
            f"Text output: ${costs['text_output']:.4f}, "
            f"Total: ${costs['total']:.4f}"
        )
        
    except Exception as e:
        print(f"Error during transcription: {e}")


if __name__ == "__main__":
    if args.file:
        # If a file is specified, just transcribe it and exit
        transcribe_file(args.file)
    else:
        try:
            # Start listening for the hotkey
            with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
                print("Listening for hotkey...")
                listener.join()
        except KeyboardInterrupt:
            print("Exiting...")
            sys.exit(0)
