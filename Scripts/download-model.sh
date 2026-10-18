#!/bin/zsh
# download-model.sh
# Lädt Wads Sprachmodell vom offiziellen whisper.cpp-Bereich auf Hugging Face nach Models/
# und bricht ab, wenn die Prüfsumme nicht mit der veröffentlichten übereinstimmt.
# Das Modell ist zu groß für Git und wird deshalb nach dem Klonen einmal so geholt.

set -euo pipefail
cd "${0:A:h}/.."

name=ggml-large-v3-turbo-q5_0.bin
sha256=394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2

mkdir -p Models
curl -L --fail -o "Models/$name" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$name"
echo "$sha256  Models/$name" | shasum -a 256 -c -
