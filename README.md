# Whisperer

A macOS menu bar app that transcribes speech types the transcribed text into the active text field.

## Features

- Lives in your menu bar for easy access
- Hold the right Option key to start recording your voice
- Automatically transcribes your speech using OpenAI's GPT-4o-transcribe model
- Injects the transcribed text into your active text field 
- Works system-wide in any application
- Configurable prompt for improved transcription context
- Tracks usage metrics including total transcriptions, time, and cost
- Completely open source with no external dependencies

## Requirements

- macOS 13.0 or later
- OpenAI API key
- Swift 6.0+ toolchain for building

## Setup

1. Clone the repository
2. Run `swift run` to start the app
3. Open the menubar app, input and test your OpenAI API key
4. Grant accessibility permissions to the program that's running the app; this might be your IDE or terminal.

## Usage

1. Click the Whisperer icon in your menu bar to open the interface
2. Click where you want text to appear
3. Hold down the right Option key and speak
4. Release the Option key when you're done
5. The transcribed text will be typed into your active application

## Privacy

- Audio is only recorded while you hold the right Option key
- Your API key is stored locally on your device
- No data is sent to or stored on remote servers other than what is processed by OpenAI

## Troubleshooting

- If text isn't appearing, make sure you've granted Accessibility permissions
- If the app isn't responding to the right Option key, try restarting the app
- Check the OpenAI API key in settings if transcription isn't working
- Use the "Test" button in Settings to verify your API key is valid
- Make sure your internet connection is stable for WebSocket communication
- Consider using a more specific custom prompt for better transcription of domain-specific terms 
