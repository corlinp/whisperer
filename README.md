# Whisperer

Usable voice-to-text for everyday writing. Magnitudes better than built-in dictation on Mac.

When whisperer running, you can press or press-and-hold the right option key on your mac and start talking. When you're done, you can press the right option key again to stop recording. The text will be written to whatever window you're in.

Whisperer uses OpenAI's Whisper running locally in pytorch and can be prompted to better handle technical jargon.

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


## Installation

Whisperer runs in Python 3.10 (not 3.11, yet). You can install it on Mac with the included install.sh script.

