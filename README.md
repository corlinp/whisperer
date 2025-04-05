# Voibe

A Mac-native productivity app that types what you say into into the active text field. Hold the right option key and talk, release to transcribe. Uses gpt-4o and your OpenAI API Key.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b1970917-2026-4434-b881-6cd11a8102c1" width="400">
</p>

## Features

- Lives in your menu bar for easy access
- Input device select
- Transcribes your speech using OpenAI's GPT-4o-transcribe model
- Injects the transcribed text into your active text field 
- Works system-wide in any application
- Configurable prompt for improved transcription context
- Tracks usage metrics including total transcriptions, time, and cost
- Completely open source, written in Swift 6 with no external dependencies / libraries

## Requirements

- macOS 13.0 or later
- OpenAI API key
- Swift 6.0+ toolchain for building

## Setup

1. Clone the repository
2. Run `swift run` to start the app
3. Grant accessibility permissions to the program that's running the app; this might be your IDE or terminal
4. Open the menubar app, input and test your OpenAI API key
5. Select your audio input device at the top, if not default
6. (optional) Enter a custom prompt with context to help 4o transcribe your speech (more info below)

## Usage

1. Click in any text field where you want text to appear
2. Use either recording mode:
   - **Hold-to-record**: Press and hold the right Option key while speaking, then release when done
   - **Toggle mode**: Quickly tap the right Option key to start recording, tap again when done
3. The transcribed text will be typed into your active application

## Privacy

- Audio is only recorded while you hold the right Option key or have toggle mode active
- Your API key is stored locally on your device
- No data is sent to or stored on remote servers other than what is processed by OpenAI

## Troubleshooting

- If text isn't appearing, make sure you've granted Accessibility permissions
- If the app isn't responding to the right Option key, try restarting the app
- Test the OpenAI API key to make sure it's valid
- If the output is nonsense, it might not be hearing you - check your input devices
- Make sure your internet connection is stable
- Consider using a more specific custom prompt for better transcription of domain-specific terms 


## Prompting

You can prompt 4o to recognize speicifc terminology, adapt to your writing style, use formatting, or recognize terms in context.

```
Return the user's input as transcribed text with minimal edits to improve formatting, grammar, self-corrections, and filler words, but maintain the original meaning and clarity.

Adhere to the following guidelines:
	- Minimal Edits: Exclude filler words such as "um," "so," "you know," and "like," unless they are essential to the meaning.
	- Accurate Representation: Repeat exactly what is said, fixing any self-corrections. Examples:
		- User: "That's on Tuesday— I mean, you know, Wednesday." Output: "That's on Wednesday."
		- User: "Where are the apples and bananas? Um, wait, not bananas" Output: "Where are the apples?"
	- Formatting Instructions: Follow ALL formatting instructions given by the user (camelCase, bullet points, parentheses, numbered lists, casing, indentation, quotes, etc.) without including the instructions in the final transcript. Examples:
		- User: "camel case order now" Output: "orderNow"
		- User: "table name lowercase underscores with parentheses" Output: "(table_name)"
	- Spelling Clarifications: Apply spelling clarifications without including the letters in the transcript. Examples:
		- User: "Tell that to Jakub, that's J-A-K-U-B," Output: "Tell that to Jakub"
		- User: "I told Sindy with an S to go ahead" Output: "I told Sindy to go ahead"
	- Contextual Precision: Accurately transcribe technical terms, acronyms, company names, or codenames to the best of your ability, even if they are unfamiliar.
	- No Extraneous Content: Provide only the transcribed text. Do not include explanations, comments, answers, or additional context. If you can't understand what is being said, don't output anything for that portion.
	- Punctuation: Full sentences can have proper punctuation, but sentence fragments do not need to start with a capital letter or end with punctuation.

You are transcribing the text for a software engineer.

Some commonly used terms are Voibe (a transcription app), etc...
```
