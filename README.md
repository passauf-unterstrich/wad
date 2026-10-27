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
- **Freies Diktieren:** Zweimal kurz die rechte Option-Taste tippen (oder im Menü *Freies Diktieren starten* wählen) und ohne Taste sprechen. Das Vorschau-Fenster zeigt live mit, der fertige Text landet in der Zwischenablage, eingefügt wird nichts, egal was unter *Einfügemodus* eingestellt ist. Beenden mit *Freies Diktieren stoppen* oder einmal kurz der rechten Option-Taste. Als Tipp zählt nur die rechte Option-Taste allein, ohne andere Tasten dazwischen; ⌥⇧-Fenster-Kürzel und Sonderzeichen wie ⌥L lösen also nichts aus. Nach der Höchstdauer (2, 5 oder 10 Minuten, Standard 5, einstellbar im Menü unter *Höchstdauer freies Diktieren*) stoppt Wad von selbst.
- **Endet eine Aufnahme ungewollt**, etwa weil der Mac gesperrt wird oder das Mikrofon wegfällt, geht nichts verloren: Wad fügt das Gesagte ein oder legt es, auf dem Sperrbildschirm, unter *Letzte Diktate* ab (ist dort *Mitschreiben* aus, wird es verworfen). Oben im Menü steht der Grund, und ein kurzer Ton weist darauf hin.
- **Einfügemodus** (im Menü): *Während des Diktats* (voreingestellt) fügt Wad schon an jeder Sprechpause das Gesagte ein. *Nach dem Diktat* kommt der ganze Text erst nach dem Loslassen. *Nur in die Zwischenablage* legt den Text dort ab, eingefügt wird nichts. *Zwischenablage mit Vorschau* zeigt dazu ein kleines Fenster, in dem du live mitliest (siehe *Vorschau-Fenster*).
- **Vorschau-Fenster** (bei *Zwischenablage mit Vorschau* und beim freien Diktieren): ein kleiner Notizzettel. Fertiger Text ist schwarz bzw. weiß und lässt sich sofort korrigieren, auch während du weitersprichst; grau ist, was Wad noch nicht sicher erkannt hat. Jedes weitere Diktat kommt auf denselben Zettel: ans Ende, oder an die Stelle, an die du im Fenster den Cursor gesetzt hast. Solange du im Fenster bist, diktierst du immer dort hinein, nie in eine andere App. Nach jedem Diktat liegt der ganze Zettel in der Zwischenablage. *Einfügen* (⌘↩) heißt: fertig. Der Zettel kommt endgültig in die Zwischenablage, das Fenster schließt, und das nächste Diktat beginnt einen neuen Zettel. Einfügen kannst du ihn dann wie gewohnt mit ⌘V. *Kopieren* legt ihn nur in die Zwischenablage, der Zettel bleibt. Hört Wad bei einem der beiden Knöpfe noch zu, beendet es zuerst die Aufnahme und nimmt das letzte Wort noch mit. ✕ schließt das Fenster und beginnt ebenfalls einen neuen Zettel. Fertige Zettel kommen unter *Letzte Diktate*, und mit ‹ › oben im Fenster blätterst du durch sie zurück und wieder vor (nur, wenn dort *Mitschreiben* an ist).
- **Kleinschreibung**: schreibt jedes Diktat komplett klein. Wad merkt sich diesen Schalter auch nach einem Neustart.
- **Vokabeln**: Ein Wort falsch erkannt? Markieren und **⌃⌥W** drücken (Ctrl+Option+W). Im Fenster die richtige Schreibweise eintragen und wählen, ob Wad sie sich *nur bis zum Neustart* oder *immer* merkt. Das markierte Wort im Text ersetzt Wad dabei gleich mit, nur an dieser einen Stelle. Wad ersetzt das Falsche künftig und gibt dem Modell die richtigen Schreibweisen als Hinweis mit. Die Liste ist die Textdatei `Vokabeln.txt` (Menü *Vokabeln → Vokabelliste im Finder zeigen*), eine Zeile pro Eintrag: `Begriff` oder `Falsch -> Richtig`. *Vorlage für deine KI kopieren* liefert einen Auftrag, mit dem ChatGPT oder Claude dir eine passende Liste erstellt.
- **Sprache** (im Menü): Deutsch ist voreingestellt, dazu Englisch, Französisch und Spanisch. Mit *Sprachoffen* erkennt Wad die Sprache jedes Diktats selbst.
- Kurzes Antippen der Taste löst nichts aus.
- **Letzte Diktate** und **Zwischenablage-Verlauf** im Menü zeigen jeweils die letzten 20 Einträge. Ein Klick legt den Text wieder in die Zwischenablage. Oben in jedem der beiden Untermenüs schaltet *Mitschreiben* den Verlauf einzeln ab oder wieder an. Ausschalten leert ihn sofort; ist der Zwischenablage-Verlauf aus, liest Wad die Zwischenablage gar nicht mehr mit.
- **Fenstermanager** (ab Werk an): Mit Tastenkürzeln schiebst du das vordere Fenster an eine feste Stelle.
  - **⌘⇧F** Vollbild, **⌘⇧ + Pfeiltaste** linke, rechte, obere oder untere Hälfte. Drückst du dasselbe Kürzel noch einmal, wechselt die Breite zwischen ½, ⅔ und ⅓.
  - **⌥⇧ + Pfeiltaste** Viertel: ← oben links, ↑ oben rechts, → unten rechts, ↓ unten links.
  - **⌃⌥C** zentriert das Fenster.
  - **Gut zu wissen:** Dieselben Kürzel benutzt macOS normalerweise zum Markieren von Text (⌘⇧ + Pfeil bis zum Zeilen- oder Textende, ⌥⇧ + Pfeil wortweise). Solange der Fenstermanager an ist, bewegen sie stattdessen das Fenster. Wenn du so markierst, belege die Kürzel im Menü unter *Fenstermanager → Kürzel …* um, oder schalte dort *Eingeschaltet* aus.
- **Updates**: Nur wenn du es einschaltest, sieht Wad einmal am Tag nach, ob es eine neue Version gibt, und zeigt dann ein kleines Fenster mit *Zum Download* (öffnet https://linushundt.com/wad/download/ im Browser), *Später* und *Diese Version überspringen*. Wad lädt und installiert nie selbst etwas. Was sich geändert hat, steht im Menü unter *Updates → Was ist neu …*.
- **Bei Anmeldung starten** (ab Werk an, sobald Wad im Ordner Programme liegt): Wad startet nach dem Anmelden von selbst. Abschalten im Menü oder unter Systemeinstellungen → Allgemein → Anmeldeobjekte.

Die Zwischenablage nutzt Wad nur für einen Augenblick zum Einfügen und stellt danach wieder her, was vorher drin war, auch Bilder und Dateien.

## Wo liegen die Daten?

**Was ist der Arbeitsspeicher?** Der Mac hat zwei Arten von Speicher. Die *Festplatte* ist das, was du im Finder siehst: Dateien und Ordner, die einen Neustart überstehen. Der *Arbeitsspeicher* ist ein separater, flüchtiger Speicher, den jedes laufende Programm als Notizblock benutzt. Er hat keine Dateien und keine Ordner und taucht deshalb nirgends im Finder auf. Was dort liegt, verschwindet, sobald das Programm beendet wird, und spätestens beim Ausschalten des Mac.

**Wer kann darauf zugreifen?** macOS gibt jedem Programm seinen eigenen, abgeschotteten Bereich im Arbeitsspeicher. Andere Programme können ihn nicht lesen.

**Was Wad wo speichert:**
- **Audio:** nur im Arbeitsspeicher. Es wird nie eine Audiodatei geschrieben, auch keine vorübergehende. Jedes Stück wird direkt nach der Umwandlung mit Nullen überschrieben.
- **Verläufe** (letzte 20 Diktate, letzte 20 kopierte Texte): nur im Arbeitsspeicher. Nach dem Beenden von Wad oder einem Neustart des Mac sind sie leer. Passwörter aus Passwort-Managern landen nie im Verlauf.
- **Auf der Festplatte:** nur Wads Einstellungen in den macOS-Einstellungen (Sprache, Einfügemodus, Kleinschreibung, ob die beiden Verläufe mitschreiben, Fenstermanager an oder aus, eigene Fenster-Kürzel, Höchstdauer fürs freie Diktieren, Update-Prüfung an oder aus mit Zeitpunkt der letzten Prüfung und angekündigter oder übersprungener Version, und interne Merker: zuletzt gestartete Version, ob der Start bei Anmeldung eingerichtet und ob nach der alten App gesucht wurde) sowie die Vokabeln, die du *immer* merken lässt, in `~/Library/Application Support/Wad/Vokabeln.txt`. Es gibt keinen Ort mit Diktaten, Aufnahmen oder Zwischenablage-Inhalten.

**Zwei ehrliche Grenzen:**
- Wird der Arbeitsspeicher knapp, lagert macOS selten genutzte Teile vorübergehend verschlüsselt auf die Festplatte aus. Diese Auslagerung wird beim Neustart verworfen und ist für Programme und den Finder nicht lesbar.
- Text, den Wad in eine andere App einfügt, speichert natürlich diese App.

## Sicherheit

- **Netzwerk nur für Updates, und nur wenn du es willst.** Ist *Updates → Automatisch suchen* an (ab Werk aus, Wad weist beim ersten Start einmal darauf hin), fragt Wad höchstens einmal am Tag bei GitHub nach der neuesten Versionsnummer, ebenso wenn du *Updates → Jetzt suchen …* wählst. Dabei sieht GitHub, wie bei jeder Website, deine IP-Adresse und die Uhrzeit, dazu die Kennung „Wad/<Version>“. Diktate, Vokabeln, Einstellungen oder Daten über dich werden nie gesendet. Sonst gibt es keinen Netzwerkcode: keine Analyse, keine Absturzberichte. Ein- und ausschalten: im Menü der Haken bei *Updates → Automatisch suchen*. Der ganze Netzwerkcode steht in einer Datei, `Wad/UpdateChecker.swift`, und lässt sich dort prüfen.
- **Nur die eine Taste.** Wad beobachtet ausschließlich Sondertasten wie Shift oder Option und wertet nur die rechte Option-Taste aus. Welche Buchstaben du tippst, sieht Wad technisch nie. Für den Doppeltipp fragt Wad beim System nur nach, wie lange der letzte Tastenanschlag her ist, nicht welcher es war.
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
