# Wad

Diktieren auf dem Mac mit einer einzigen Taste. Rechte Option-Taste halten, sprechen, loslassen: Der Text erscheint dort, wo der Cursor steht, egal in welcher App. Die Spracherkennung läuft vollständig auf deinem Mac, nichts verlässt ihn.

Der Name spielt auf den Film „Der Diktator“ und das Land Wadiya an.

## Was du brauchst

- Einen Mac mit Apple-Chip (M1 oder neuer). Auf Intel-Macs zeigt Wad nur einen Hinweis.
- macOS 14 (Sonoma) oder neuer.
- Etwa 600 MB freien Speicher, das Sprachmodell steckt in der App.

## Installieren

1. `Wad.dmg` öffnen und **Wad** in den Ordner **Programme** ziehen.
2. Wad aus dem Ordner Programme starten. In der Menüleiste erscheint ein Mikrofon mit Stern.
3. Wad fragt nach zwei Berechtigungen, beide sind nötig:
   - **Mikrofon**, um dich zu hören, solange du die Taste hältst.
   - **Bedienungshilfen**, um die rechte Option-Taste zu erkennen und den Text einzufügen. Klicke im Dialog auf *Systemeinstellungen öffnen* und schalte Wad ein. Wad startet sich danach einmal selbst neu.

## Benutzen

- **Rechte Option-Taste halten und sprechen.** Das Symbol wird zum roten Punkt, und macOS zeigt oben rechts den orangen Mikrofon-Punkt. Beim Loslassen verschwinden beide sofort.
- **Live** (voreingestellt): Schon während du sprichst, fügt Wad an jeder Sprechpause das Gesagte ein.
- **Am Ende einfügen**: Der ganze Text kommt erst nach dem Loslassen. Umschalten unter *Modus* im Menü.
- Kurzes Antippen der Taste löst nichts aus.
- **Letzte Diktate** und **Zwischenablage-Verlauf** im Menü zeigen jeweils die letzten 20 Einträge. Ein Klick legt den Text wieder in die Zwischenablage.

Die Zwischenablage nutzt Wad nur für einen Augenblick zum Einfügen und stellt danach wieder her, was vorher drin war, auch Bilder und Dateien.

## Wo liegen die Daten?

**Was ist der Arbeitsspeicher?** Der Mac hat zwei Arten von Speicher. Die *Festplatte* ist das, was du im Finder siehst: Dateien und Ordner, die einen Neustart überstehen. Der *Arbeitsspeicher* ist ein separater, flüchtiger Speicher, den jedes laufende Programm als Notizblock benutzt. Er hat keine Dateien und keine Ordner und taucht deshalb nirgends im Finder auf. Was dort liegt, verschwindet, sobald das Programm beendet wird, und spätestens beim Ausschalten des Mac.

**Wer kann darauf zugreifen?** macOS gibt jedem Programm seinen eigenen, abgeschotteten Bereich im Arbeitsspeicher. Andere Programme können ihn nicht lesen.

**Was Wad wo speichert:**
- **Audio:** nur im Arbeitsspeicher. Es wird nie eine Audiodatei geschrieben, auch keine vorübergehende. Jedes Stück wird direkt nach der Umwandlung mit Nullen überschrieben.
- **Verläufe** (letzte 20 Diktate, letzte 20 kopierte Texte): nur im Arbeitsspeicher. Nach dem Beenden von Wad oder einem Neustart des Mac sind sie leer. Passwörter aus Passwort-Managern landen nie im Verlauf.
- **Auf der Festplatte:** nichts. Es gibt keinen Ort mit Diktaten, Aufnahmen oder Zwischenablage-Inhalten.

**Zwei ehrliche Grenzen:**
- Wird der Arbeitsspeicher knapp, lagert macOS selten genutzte Teile vorübergehend verschlüsselt auf die Festplatte aus. Diese Auslagerung wird beim Neustart verworfen und ist für Programme und den Finder nicht lesbar.
- Text, den Wad in eine andere App einfügt, speichert natürlich diese App.

## Sicherheit

- **Kein Netzwerk.** Wad enthält keinen Netzwerkcode: keine Analyse, keine Absturzberichte, keine Update-Prüfung. Das lässt sich im Quelltext prüfen.
- **Nur die eine Taste.** Wad beobachtet ausschließlich Sondertasten wie Shift oder Option und wertet nur die rechte Option-Taste aus. Welche Buchstaben du tippst, sieht Wad technisch nie.
- **Mikrofon nur beim Halten.** Fünf Absicherungen verhindern, dass eine Aufnahme weiterläuft: Wad fragt fünfmal pro Sekunde nach, ob die Taste wirklich noch gedrückt ist. Nach spätestens 10 Minuten endet jede Aufnahme. Ruhezustand, Bildschirmsperre und Benutzerwechsel beenden sie sofort. Ein einziger Zustandsautomat startet das Mikrofon. Und Wad ist ein einziges Programm ohne Hilfsprozesse.

## Selbst bauen

Voraussetzungen: Xcode und CMake (`brew install cmake`).

```bash
git clone --recurse-submodules https://github.com/<benutzername>/wad.git
cd wad
./Scripts/download-model.sh      # Sprachmodelle laden, Prüfsummen kontrollieren
./Scripts/build-whisper.sh       # whisper.cpp übersetzen
open Wad.xcodeproj
```

Die Spracherkennung stammt von [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT-Lizenz) mit dem Modell Whisper large-v3-turbo und dem Sprachdetektor Silero VAD.

## Lizenz

Wad steht unter der [GPL-3.0](LICENSE). Du darfst Wad benutzen, verändern und weitergeben. Wer Wad weitergibt, auch verändert, muss es ebenfalls offen und unter derselben Lizenz weitergeben.
