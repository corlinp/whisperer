brew install python@3.10
brew install portaudio
pip3.10 install numpy pyaudio pyautogui pynput whisper-openai

# where am I located?
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# put the run.sh script as an alias called 'whisperer' in the .zshrc
echo "alias whisperer='sh $DIR/run.sh'" >> ~/.zshrc
# source the .zshrc
source ~/.zshrc

echo "Installation complete. Make sure you add the appropriate Accessibility permissions for this to work."
echo "You can do this by going to System Preferences > Security & Privacy > Privacy > Accessibility and adding iTerm or whatever terminal you're running it in."

echo "You can now run the script by typing 'whisperer' in your terminal with the prompt you want"