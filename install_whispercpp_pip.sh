#!/bin/bash

pip3.10 install whispercpp

git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make
cd models
bash ./download-ggml-model.sh small.en
