# Whisperer

Usable voice-to-text for everyday writing. Streets ahead of built-in dictation.

With whisperer running, just press (or press-and-hold) the right option key on your Mac and start talking. 

When you're done, you can release or press the key again to stop recording. The app will emulate your keyboard and text will be written to whatever textbox you have active.

Whisperer uses OpenAI's Whisper running locally in pytorch and can be prompted to better handle technical jargon. Just supply it a prompt or a `.txt` file.

## Comparison

Original Sentence:

> Popular Linux distributions include Debian, Fedora Linux, and Ubuntu. You can use windowing systems such as X11 or Wayland with a desktop environment like KDE Plasma.

iPhone Voice-to-Text:

> Popular Linux distributions include Debby and Fed or Linux, and do Bantu. You can use windowing systems such as X eleven or Weiland with a desktop environment like KD plasma.

Whisperer with the prompt "Corlin talks computer science, crypto, and physics":

> Popular Linux distributions include Debian, Fedora, Linux, and Ubuntu. You can use windowing systems such as X11 or Wayland with a desktop environment like KDE Plasma. 

Here, Whisper was clued in to me talking like a computer scientist and was able to handle the technical jargon better than the iPhone voice-to-text.

## Status

Whisperer is currently in alpha and occasionally crashes with segmentation faults. To fix this we're waiting on some patches to Pytorch on M1 Macs. We might also switch to [this](https://github.com/ggerganov/whisper.cpp) C++ implementation of Whisper some day. PRs welcome!


## Installation and Usage

```
./install.sh
echo "Talking about computers and life" > ~/whisperer_prompt.txt
whisperer ~/whisperer_prompt.txt
```

Now just try that right-option key in any text field!