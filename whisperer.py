import queue
import sys
import threading
import time
from datetime import datetime

import pyaudio
import pyautogui
import pyperclip
from pynput import keyboard
import wave
import subprocess

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

# Audio settings
CHUNK = 512
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 16000

recordings_folder = "/Users/corlinpalmer/Documents/whispers"

# if recording is shorter than this, use the base model. Else we use small.
model_duration_cutoff_secs = 8.0

def record_audio():
    """Record audio from the microphone and store it in frames."""
    global recording, stream, frames
    if not recording:
        recording = True
        stream = audio.open(format=FORMAT,
                            channels=CHANNELS,
                            rate=RATE,
                            input=True,
                            frames_per_buffer=CHUNK)
        frames = []
        print(f"Recording started after {time.time() - modifier_last_pressed:.4f}s.")

    while recording:
        data = stream.read(CHUNK)
        frames.append(data)
    else:
        stop_recording()

def process_and_clear_frames():
    global frames
    fname = f"{recordings_folder}/recording_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.wav"
    with wave.open(fname, "wb") as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(audio.get_sample_size(FORMAT))
        f.setframerate(RATE)
        f.writeframes(b"".join(frames))
    duration = (len(frames)*CHUNK) / RATE
    audio_queue.put((fname, duration))
    frames = []

def stop_recording():
    global recording, stream
    stream.stop_stream()
    stream.close()
    if len(frames) > 0:
        process_and_clear_frames()

def process_audio_whispercpp():
    """Continuously process audio from the queue and transcribe it."""
    global audio_queue
    while True:
        fname, orig_duration = audio_queue.get()
        t0 = time.time()
        model = "small.en"
        if orig_duration < model_duration_cutoff_secs:
            model = "base.en"
        print("Transcribing audio with whispercpp...")
        cmd = ['/Users/corlinpalmer/Documents/GitHub/whisperer/whisper.cpp/main',
            '-m', f'/Users/corlinpalmer/Documents/GitHub/whisperer/whisper.cpp/models/ggml-{model}.bin',
            '-f', fname,
            '--prompt', prompt,
            '-nt', '-otxt'
        ]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # print stdout and stderr
        # print(result.stdout)
        print(result.stderr)
        result.check_returncode()
        output_file = fname+".txt"
        # read the file
        with open(output_file) as f:
            transcription = f.read()
        
        t1 = time.time()
        transcribe_duration = t1 - t0
        print(f"Audio: {orig_duration:.2f}s, Transcription: {transcribe_duration:.2f}s, Speedup: {orig_duration / transcribe_duration:.2f}x")
        transcription = transcription.strip().replace("\n", " ").replace("  ", " ")
        if len(transcription) == 0:
            transcription = " "
        else:
            transcription = transcription[0].upper() + transcription[1:] + " "
        # pyautogui.write(transcription)
        # instead of write (which is slow and buggy), use pyperclip
        print(f"\n{transcription}\n\n")
        pyperclip.copy(transcription)
        while modifier_pressed:
            time.sleep(0.02)
        pyautogui.hotkey("command", "v")


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
        if time.time() - modifier_last_pressed < 0.5:
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