# Whisperer

A macOS menu bar app that transcribes speech in real-time and types the transcribed text into the active text field.

## Features

- Lives in your menu bar for easy access
- Hold the right Option key to start recording your voice
- Automatically transcribes your speech using OpenAI's GPT-4o-transcribe model
- Injects the transcribed text into your active text field 
- Works system-wide in any application

## Requirements

- macOS 13.0 or later
- OpenAI API key with access to the gpt-4o-transcribe model
- Xcode 15 or Swift 5.9+ toolchain for building

## Setup

### Building from Source

1. Clone the repository
2. Run `swift build` to build the app
3. Run `swift run` to start the app

### Setting up Your API Key

1. Click on the Whisperer menu bar icon
2. Click on the settings icon (gear)
3. Enter your OpenAI API key
4. The app will automatically save your key

### Granting Permissions

Whisperer requires the following permissions to function:

1. **Microphone access** - For capturing your voice
2. **Accessibility access** - For monitoring the right Option key and injecting text

To grant Accessibility access:
1. Click on the "Open Accessibility Settings" button in the app
2. Add Whisperer to the list of allowed applications

## Usage

1. Click the Whisperer icon in your menu bar to see its status
2. Position your cursor where you want text to appear
3. Hold down the right Option key and speak
4. Release the Option key when you're done
5. The transcribed text will be typed into your active application

## How It Works

- The app monitors system-wide key events to detect when you press the right Option key
- When the key is pressed, it starts recording audio from your microphone
- The audio is streamed to OpenAI's GPT-4o-transcribe API for real-time transcription
- As text is transcribed, it's injected into your active text field as if you were typing

## Privacy

- Audio is only recorded while you hold the right Option key
- Your API key is stored locally on your device
- No data is stored on remote servers other than what is processed by OpenAI

## Troubleshooting

- If text isn't appearing, make sure you've granted Accessibility permissions
- If the app isn't responding to the right Option key, try restarting the app
- Check the OpenAI API key in settings if transcription isn't working 