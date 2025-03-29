# Whisperer

A macOS menu bar app that transcribes speech types the transcribed text into the active text field.

## Features

- Lives in your menu bar for easy access
- Two recording modes:
  - Hold the right Option key to record (hold-to-record)
  - Quickly tap the right Option key to start recording, tap again to stop (toggle mode)
- Select your preferred input device directly from the menu bar
- Automatically stops recording after 5 minutes to prevent accidental long recordings
- Automatically transcribes your speech using OpenAI's GPT-4o-transcribe model
- Injects the transcribed text into your active text field 
- Works system-wide in any application
- Configurable prompt for improved transcription context
- Tracks usage metrics including total transcriptions, time, and cost
- Ignores recordings under 0.5 seconds in hold-to-record mode to prevent accidental transcriptions
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
2. Click "Input Devices" to select your preferred audio input source
3. Click where you want text to appear
4. Use either recording mode:
   - **Hold-to-record**: Press and hold the right Option key while speaking, then release when done
   - **Toggle mode**: Quickly tap the right Option key to start recording, tap again when done
5. The transcribed text will be typed into your active application
6. Recording automatically stops after 5 minutes if not manually stopped

## Privacy

- Audio is only recorded while you hold the right Option key or have toggle mode active
- Your API key is stored locally on your device
- No data is sent to or stored on remote servers other than what is processed by OpenAI

## Troubleshooting

- If text isn't appearing, make sure you've granted Accessibility permissions
- If the app isn't responding to the right Option key, try restarting the app
- Check the OpenAI API key in settings if transcription isn't working
- Use the "Test" button in Settings to verify your API key is valid
- Make sure your internet connection is stable for WebSocket communication
- If audio recording fails, try selecting a different input device from the menu
- Consider using a more specific custom prompt for better transcription of domain-specific terms 


## Example Prompt

```
Return the user's input as transcribed text with minimal edits to improve formatting, grammar, self-corrections, and filler words, but maintain the original meaning and clarity.

Adhere to the following guidelines:
	- Minimal Edits: Exclude filler words such as "um," "so," "you know," and "like," unless they are essential to the meaning.
	- Accurate Representation: Repeat exactly what is said, fixing any self-corrections. Examples:
		- User: "So I'm going to McDonald's— I mean, you know, Burger King" Output: "I'm going to Burger King."
		- User: "Where are the apples and bananas? Eh, wait, not bananas" Output: "Where are the apples?"
	- Formatting Instructions: Follow ALL formatting instructions given by the user (camelCase, bullet points, parentheses, numbered lists, casing, indentation, quotes, etc.) without including these instructions in the final transcript. Examples:
		- User: "create a bullet list of three items hamburger hotdog sandwich" Output: "• Hamburger\n• Hot Dog\n• Sandwich"
		- User: "camel case order now" Output: "orderNow"
		- User: "table name lowercase underscores with parentheses" Output: "(table_name)"
		- User: "let's just rearrange, I mean swap, the images" Output: "Let's just swap the images"
	- Spelling Clarifications: Apply spelling clarifications without including them in the transcript. Examples:
		- User: "Tell that to Jakub, that's J-A-K-U-B," Output: "Tell that to Jakub"
		- User: "I told Sindy with an S to go ahead" Output: "I told Sindy to go ahead"
	- Contextual Precision: Accurately transcribe technical terms, acronyms, company names, or codenames to the best of your ability, even if they are unfamiliar.
	- No Extraneous Content: Provide only the transcribed text. Do not include explanations, comments, answers, or additional context. If you can't understand what is being said, don't output anything for that portion.
	- Punctuation: Full sentences can have proper punctuation, but sentence fragments do not need to start with a capital letter or end with punctuation.
```