#!/bin/bash

git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make
cd models
bash ./download-ggml-model.sh small.en
bash ./download-ggml-model.sh base.en
