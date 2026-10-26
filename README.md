# Wad

Diktieren auf dem Mac mit einer einzigen Taste. Rechte Option-Taste halten, sprechen, loslassen: Der Text erscheint dort, wo der Cursor steht, egal in welcher App. Die Spracherkennung läuft vollständig auf deinem Mac, nichts verlässt ihn.

Der Name spielt auf den Film „Der Diktator“ und das Land Wadiya an.

## Was du brauchst

- Einen Mac mit Apple-Chip (M1 oder neuer). Auf Intel-Macs zeigt Wad nur einen Hinweis.
- macOS 14 (Sonoma) oder neuer.
- Etwa 600 MB freien Speicher, das Sprachmodell steckt in der App.

## Installieren

1. Die heruntergeladene Datei `Wad-<Version>.dmg` öffnen und **Wad** in den Ordner **Programme** ziehen. Startest du Wad versehentlich direkt aus diesem Fenster, bietet es an, sich selbst dorthin zu bewegen. Nach dem ersten Start aus dem Programme-Ordner wirft Wad das Installations-Laufwerk selbst aus.
2. Wad aus dem Ordner Programme starten. In der Menüleiste erscheint ein Mikrofon mit Stern.
3. Wad fragt nach zwei Berechtigungen, beide sind nötig:
   - **Mikrofon**, um dich zu hören, solange du die Taste hältst.
   - **Bedienungshilfen** (in neueren macOS-Versionen „Gerätesteuerung und Datenzugriff“), um die rechte Option-Taste zu erkennen, den Text einzufügen und Fenster zu verschieben. Klicke im Dialog auf *Systemeinstellungen öffnen* und schalte Wad ein. Wad startet sich danach einmal selbst neu.

## Benutzen

- **Rechte Option-Taste halten und sprechen.** Das Symbol wird zum roten Punkt, und macOS zeigt oben rechts das orange Mikrofon. Beim Loslassen verschwinden beide sofort. Solange du die Taste hältst, bleibt der Bildschirm an.
- **Freies Diktieren:** Im Menü *Aufnahme starten* wählen und ohne Taste sprechen. Beenden mit *Aufnahme stoppen* oder einmal kurz der rechten Option-Taste. Nach der *Höchstdauer* (2, 5 oder 10 Minuten, Standard 5) stoppt Wad von selbst und fügt ein.
- **Endet eine Aufnahme ungewollt**, etwa weil der Mac gesperrt wird oder das Mikrofon wegfällt, geht nichts verloren: Wad fügt das Gesagte ein oder legt es, auf dem Sperrbildschirm, unter *Letzte Diktate* ab. Oben im Menü steht der Grund, und ein kurzer Ton weist darauf hin.
- **Live** (voreingestellt): Schon während du sprichst, fügt Wad an jeder Sprechpause das Gesagte ein.
- **Am Ende einfügen**: Der ganze Text kommt erst nach dem Loslassen. Umschalten unter *Modus* im Menü.
- **Kleinschreibung**: schreibt jedes Diktat komplett klein. Wad merkt sich diesen Schalter auch nach einem Neustart.
- **Vokabeln**: Ein Wort falsch erkannt? Markieren und **⌃⌥W** drücken (Ctrl+Option+W). Im Fenster die richtige Schreibweise eintragen und wählen, ob Wad sie sich *nur bis zum Neustart* oder *immer* merkt. Das markierte Wort im Text ersetzt Wad dabei gleich mit, nur an dieser einen Stelle. Wad ersetzt das Falsche künftig und gibt dem Modell die richtigen Schreibweisen als Hinweis mit. Die Liste ist die Textdatei `Vokabeln.txt` (Menü *Vokabeln → Vokabelliste im Finder zeigen*), eine Zeile pro Eintrag: `Begriff` oder `Falsch -> Richtig`. *Vorlage für deine KI kopieren* liefert einen Auftrag, mit dem ChatGPT oder Claude dir eine passende Liste erstellt.
- **Sprachen**: Wad erkennt die Sprache jedes Diktats selbst, einstellen musst du nichts.
- Kurzes Antippen der Taste löst nichts aus.
- **Letzte Diktate** und **Zwischenablage-Verlauf** im Menü zeigen jeweils die letzten 20 Einträge. Ein Klick legt den Text wieder in die Zwischenablage.
- **Fenstermanager** (ab Werk an): Mit Tastenkürzeln schiebst du das vordere Fenster an eine feste Stelle.
  - **⌘⇧F** Vollbild, **⌘⇧ + Pfeiltaste** linke, rechte, obere oder untere Hälfte. Drückst du dasselbe Kürzel noch einmal, wechselt die Breite zwischen ½, ⅔ und ⅓.
  - **⌥⇧ + Pfeiltaste** Viertel: ← oben links, ↑ oben rechts, → unten rechts, ↓ unten links.
  - **⌃⌥C** zentriert das Fenster.
  - **Gut zu wissen:** Dieselben Kürzel benutzt macOS normalerweise zum Markieren von Text (⌘⇧ + Pfeil bis zum Zeilen- oder Textende, ⌥⇧ + Pfeil wortweise). Solange der Fenstermanager an ist, bewegen sie stattdessen das Fenster. Wenn du so markierst, belege die Kürzel unter *Fenster-Kürzel …* im Menü um, oder schalte *Fenstermanager* im Menü aus.
- **Bei Anmeldung starten** (ab Werk an, sobald Wad im Ordner Programme liegt): Wad startet nach dem Anmelden von selbst. Abschalten im Menü oder unter Systemeinstellungen → Allgemein → Anmeldeobjekte.

Die Zwischenablage nutzt Wad nur für einen Augenblick zum Einfügen und stellt danach wieder her, was vorher drin war, auch Bilder und Dateien.

## Wo liegen die Daten?

**Was ist der Arbeitsspeicher?** Der Mac hat zwei Arten von Speicher. Die *Festplatte* ist das, was du im Finder siehst: Dateien und Ordner, die einen Neustart überstehen. Der *Arbeitsspeicher* ist ein separater, flüchtiger Speicher, den jedes laufende Programm als Notizblock benutzt. Er hat keine Dateien und keine Ordner und taucht deshalb nirgends im Finder auf. Was dort liegt, verschwindet, sobald das Programm beendet wird, und spätestens beim Ausschalten des Mac.

**Wer kann darauf zugreifen?** macOS gibt jedem Programm seinen eigenen, abgeschotteten Bereich im Arbeitsspeicher. Andere Programme können ihn nicht lesen.

**Was Wad wo speichert:**
- **Audio:** nur im Arbeitsspeicher. Es wird nie eine Audiodatei geschrieben, auch keine vorübergehende. Jedes Stück wird direkt nach der Umwandlung mit Nullen überschrieben.
- **Verläufe** (letzte 20 Diktate, letzte 20 kopierte Texte): nur im Arbeitsspeicher. Nach dem Beenden von Wad oder einem Neustart des Mac sind sie leer. Passwörter aus Passwort-Managern landen nie im Verlauf.
- **Auf der Festplatte:** nur Wads Einstellungen in den macOS-Einstellungen (Kleinschreibung, Fenstermanager an oder aus, eigene Fenster-Kürzel, Höchstdauer fürs freie Diktieren und zwei interne Merker: ob der Start bei Anmeldung eingerichtet und ob nach der alten App gesucht wurde) sowie die Vokabeln, die du *immer* merken lässt, in `~/Library/Application Support/Wad/Vokabeln.txt`. Es gibt keinen Ort mit Diktaten, Aufnahmen oder Zwischenablage-Inhalten.

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
git clone --recurse-submodules https://github.com/passauf-unterstrich/wad.git
cd wad
./Scripts/download-model.sh      # Sprachmodelle laden, Prüfsummen kontrollieren
./Scripts/build-whisper.sh       # whisper.cpp übersetzen
open Wad.xcodeproj
```

Die Spracherkennung stammt von [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT-Lizenz) mit dem Modell Whisper large-v3-turbo und dem Sprachdetektor Silero VAD.

## Lizenz

Wad steht unter der [GPL-3.0](LICENSE). Du darfst Wad benutzen, verändern und weitergeben. Wer Wad weitergibt, auch verändert, muss es ebenfalls offen und unter derselben Lizenz weitergeben.
