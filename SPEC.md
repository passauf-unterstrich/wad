# Wad – Spezifikation

> **Status: FINAL, Version 1.1 (13.10.2026).** Alle Entscheidungen sind getroffen.
> Die App heißt **Wad** (Anspielung auf den Film „Der Diktator“ und das Land Wadiya). Dieser Name wird überall konsequent verwendet: App, Bundle, Menü, Repository, README.

Diese Datei ist der Auftrag für Claude Code. Sie legt fest, **was** gebaut wird, **welche Regeln** dabei nie gebrochen werden dürfen und **in welcher Reihenfolge** gebaut wird.

---

## Teil 0 – Arbeitsweise für Claude Code

1. **Eine Etappe pro Durchlauf.** Claude Code baut immer nur die aktuelle Etappe aus Teil 3 und hört dann auf. Die nächste Etappe beginnt erst, wenn Linus die vorige getestet und freigegeben hat.
2. **Laut denken wie ein Profi.** Linus will einem sehr erfahrenen Entwickler über die Schulter schauen, ohne selbst jede Zeile zu tippen. Claude Code erzählt deshalb auf Deutsch seinen Gedankengang mit, so wie ein Profi es einem Kollegen erklären würde:
   - **Was jetzt dran ist und warum:** z. B. „Als Erstes muss Wad überhaupt in der Menüleiste erscheinen. Dafür nehme ich Swift mit SwiftUI, weil …“.
   - **Entscheidungen mit Begründung:** Werkzeug, Sprache, Aufbau, und welche Alternative bewusst verworfen wurde.
   - **Terminalbefehle zeigen:** Jeder Befehl wird vor dem Ausführen gezeigt und in einem Satz erklärt („Ich lege jetzt den Projektordner an: `mkdir …`“).
   - **Zusammenhänge erklären,** wenn sie für das Verständnis wichtig sind, z. B. in Etappe 0: Was ist der Projektordner, was ist die fertige `Wad.app`, und was davon laden sich andere später herunter.
   - **Nicht jeden Mini-Schritt.** Erklärt wird der Gedankengang an den entscheidenden Stellen, nicht jede Klammer. Lieber wenige, kluge Sätze als lange Texte.
   - **Am Ende jeder Etappe:** kurz, was gebaut wurde, wie Linus es testet und was bewusst noch fehlt.
3. **Nichts über die Spezifikation hinaus.** Keine zusätzlichen Funktionen, Einstellungen oder Bibliotheken. Wenn etwas fehlt oder unklar ist, wird gefragt statt geraten.
4. **Kleine, verständliche Commits** mit deutscher Beschreibung, mindestens einer pro Etappe.
5. **Alter Code von Linus** wird nur gelesen, wenn Linus das ausdrücklich sagt (vermutlich in Etappe 5 als Vorlage für das Live-Chunking).
6. **Lesbarer Code vor cleverem Code.** Jede Datei hat eine klare Aufgabe und einen kurzen Kopfkommentar, der diese Aufgabe beschreibt.
7. **Designprinzip „vorausschauend“.** Wad sieht Probleme voraus und geht freundlich damit um, statt abzustürzen oder still zu versagen. Jede Etappe überlegt: Was kann hier schiefgehen, und was sieht der Nutzer dann? Beispiele, die mindestens abgedeckt sein müssen:
   - Mac mit Intel-Prozessor: Wad zeigt beim Start einen klaren Hinweis, dass ein Mac mit M1-Chip oder neuer nötig ist, und beendet sich (siehe 2.8).
   - Fehlende Berechtigung: Hinweis im Menü mit Klick direkt zur richtigen Systemeinstellung.
   - Kein Mikrofon verfügbar oder Mikrofon wechselt während der Aufnahme (z. B. AirPods): Aufnahme endet sauber, kurzer Hinweis.
   - Modell kann nicht geladen werden oder zu wenig Arbeitsspeicher: verständliche Meldung statt Absturz.
   - Taste wird nur ganz kurz angetippt (unter ca. 0,3 Sekunden): nichts passiert, kein leeres Einfügen.
8. **Designprinzip „Apple-artig“.** Die Oberfläche ist minimalistisch, aber intelligent und auf den Nutzer zugeschnitten: so wenig wie möglich sichtbar, alles Sichtbare sofort verständlich, mit Apple-Bausteinen (SF Symbols, native Menüs, Systemschrift, Systemsprache Deutsch). Wad soll sich anfühlen, als käme es von Apple selbst.
9. **Solide vor schnell.** Es geht nicht darum, schnell fertig zu werden, sondern darum, Wad so sauber zu bauen, wie es ein Spitzen-Entwickler tun würde: an alles denken, aber nichts Überflüssiges einbauen. Keine unnötigen Schleifen, keine Abfragen im Dauerlauf, wo ein Ereignis reicht (bewusste Ausnahmen: die Sicherheits-Gegenprüfung während der Aufnahme aus 2.2 und die Zwischenablage, für die macOS kein Ereignis anbietet), kein toter Code, keine Ausgaben ohne Zweck, keine Abstraktion auf Vorrat. Jede Zeile hat einen Grund.

---

## Teil 1 – Funktionsumfang

Bewusst nicht mehr als das, was hier steht.

### 1.1 Grundprinzip
Wad lebt ausschließlich in der Menüleiste (kein Dock-Symbol, kein Fenster). Solange die **rechte Option-Taste** gedrückt gehalten wird, nimmt Wad auf. Das Gesprochene wird lokal auf dem Mac in Text umgewandelt und dort eingefügt, wo gerade der Cursor steht, egal in welcher App (Notizen, WhatsApp, Claude, Browser usw.).

### 1.2 Menüleisten-Symbol
- Ruhezustand: Mikrofon-Symbol (SF Symbol, im Apple-Stil).
- Während der Aufnahme: roter Aufnahme-Kreis.
- Während die letzten Sekunden noch verarbeitet werden: dezenter Hinweis (z. B. Mikrofon mit Punkten).
- App ausgeschaltet: durchgestrichenes Mikrofon.

### 1.3 Dropdown-Menü (schlicht, Apple-typisch)
1. **Diktieren an / aus** (Schalter). Ist es aus, reagiert Wad nicht auf die Taste.
2. **Sprache ▸** Deutsch (Standard), Englisch, Französisch, Spanisch, Sprachoffen.
3. **Einfügen ▸** *Während des Diktats* (Standard), *Nach dem Diktat*, *Nur in die Zwischenablage*, *Zwischenablage mit Vorschau*.
3a. **Kleinschreibung** (Schalter, Ergänzung vom 18.10.2026 auf Linus' Wunsch): schreibt jedes Diktat komplett klein. Wad merkt sich diesen Schalter über einen Neustart hinweg, als einzigen Ja/Nein-Wert in den macOS-Einstellungen, nie als Text.
3b. **Vokabeln ▸** (Ergänzung vom 19.10.2026 auf Linus' Wunsch): *Korrigieren …* (⌃⌥W, liest das markierte Wort über die Bedienungshilfen), *Vokabelliste öffnen*, *Vorlage für deine KI kopieren*. Einträge gelten nur bis zum Neustart oder dauerhaft in `~/Library/Application Support/Wad/Vokabeln.txt`. Wad ersetzt falsche Schreibweisen als ganze Wörter und gibt dem Modell höchstens 40 richtige Schreibweisen als Hinweis. Kleinschreibung wirkt danach und gewinnt immer.
4. **Letzte Diktate ▸** bis zu 20 Einträge, neuester oben. Klick kopiert den Text in die Zwischenablage. Darunter: *Diktate löschen*.
5. **Zwischenablage-Verlauf ▸** die letzten 20 kopierten Texte, neuester oben. Klick legt den Eintrag wieder in die Zwischenablage. Darunter: *Verlauf löschen*.
6. **Fenstermanager an / aus** (Schalter, ab Etappe 9, standardmäßig an). Ist er aus, sind seine Kürzel nicht registriert. Darunter: *Fenster-Kürzel …* (siehe 1.8).
7. Hinweiszeile, falls eine Berechtigung fehlt, mit Klick direkt zur passenden Systemeinstellung.
3c. **Aufnahme starten (freies Diktieren) / Aufnahme stoppen** und **Höchstdauer freies Diktieren ▸** (Ergänzung vom 21.10.2026 auf Linus' Wunsch): freies Diktieren ohne gehaltene Taste. Stopp über das Menü oder einen kurzen Druck auf die rechte Option-Taste. Höchstdauer 2, 5 oder 10 Minuten (Standard 5), danach stoppt Wad und meldet es. Freies Diktieren läuft immer wie *Zwischenablage mit Vorschau* (1.4, 1.10): live mit grauem Entwurf im Vorschau-Fenster, der fertige Text bleibt in der Zwischenablage, eingefügt wird nichts (Ergänzung vom 26.10.2026 auf Linus' Wunsch). Der eingestellte Einfügemodus bleibt dabei unverändert; das nächste Diktat mit gehaltener Taste folgt wieder ihm. Alle Absicherungen aus 2.2 außer der Tasten-Gegenprüfung gelten weiter; die harte Grenze von 10 Minuten bleibt.
7a. **Bei Anmeldung starten** (Schalter, Ergänzung vom 19.10.2026 auf Linus' Wunsch, standardmäßig an, sobald Wad im Programme-Ordner liegt): meldet Wad über Apples Anmeldeobjekte an (`SMAppService`). macOS startet Wad dann nach der Anmeldung genau einmal, wie jede andere App in dieser Liste; Wad hat dafür keinen eigenen Hilfsprozess.
8. **Beenden.**

### 1.4 Modi
- **Während des Diktats (Standard):** Während man spricht, wird die Aufnahme an natürlichen Sprechpausen in Stücke geteilt. Jedes fertige Stück wird sofort umgewandelt und eingefügt, während man weiterspricht. Ziel: mindestens so gut wie Linus' alte Version, also keine abgeschnittenen Wörter, keine doppelten Wörter an den Übergängen, saubere Leerzeichen zwischen den Stücken.
- **Nach dem Diktat:** Alles wird erst nach dem Loslassen umgewandelt und als Ganzes eingefügt.
- **Nur in die Zwischenablage:** Nach dem Loslassen wird alles umgewandelt und dauerhaft in die Zwischenablage gelegt, eingefügt wird nichts. Der alte Inhalt der Zwischenablage ist dann bewusst weg. Der Text ist ein normaler (nicht vorübergehender) Eintrag, erscheint aber nicht zusätzlich im Zwischenablage-Verlauf von Wad, weil er schon unter „Letzte Diktate“ steht.
- **Zwischenablage mit Vorschau:** wie *Nur in die Zwischenablage*, dazu zeigt das Vorschau-Fenster (1.10) den Text, immer live.
- Freies Diktieren (3c) gilt immer als *Zwischenablage mit Vorschau*, egal welcher Modus eingestellt ist. Die Einstellung ändert sich dadurch nicht.
- Sprache und Einfügemodus merkt sich Wad pro macOS-Benutzer (UserDefaults). Ein Wechsel während einer Aufnahme gilt ab dem nächsten Diktat.
- Bei gesperrtem Bildschirm kommt nichts in die Zwischenablage, der Text liegt unter „Letzte Diktate“.

### 1.5 Spracherkennung
- Läuft vollständig lokal mit einem Whisper-Modell über **whisper.cpp** (MIT-Lizenz, nutzt die Grafikeinheit des Mac über Metal).
- Modell: **Whisper large-v3-turbo, komprimiert (q5_0), ca. 550 MB.** Das Modell ist in der App enthalten, nichts wird nachgeladen.
- Die Spracherkennung sitzt hinter genau einer Schnittstelle im Code („Transkribierer“). So kann später ein anderes Modell eingesetzt werden, ohne den Rest der App anzufassen. In Etappe 3 prüft Linus die Qualität mit seiner eigenen Stimme. Falls large-v3-turbo enttäuscht, ist NVIDIA Parakeet (v3, mehrsprachig, sehr schnell auf Apple Silicon) der erste Kandidat für einen Vergleich. Gewechselt wird nur nach Linus' Entscheidung.
- Sprache: fest gewählt im Menü (Standard Deutsch) und so an das Modell gegeben. Grund: Whisper erkennt die Sprache sonst an den ersten Sekunden und rät bei kurzen Sätzen oder englischem Anfang falsch, dann schreibt es Deutsch auf Englisch. Mit *Sprachoffen* erkennt Wad die Sprache am Anfang jedes Diktats selbst und behält sie für dieses Diktat bei.
- Bekannte Whisper-Halluzinationen bei Stille (z. B. „Untertitel im Auftrag des ZDF“, „Vielen Dank fürs Zuschauen“) werden verhindert, indem Stücke ohne erkannte Sprache gar nicht erst an das Modell gehen.

### 1.6 Verläufe
- **Diktate:** die letzten 20 fertigen Diktate als Text.
- **Zwischenablage:** die letzten 20 Texte, die der Nutzer selbst kopiert hat (nur Text, keine Bilder oder Dateien).
- Speicherort: **nur im Arbeitsspeicher.** Solange Wad läuft, sind beide Verläufe jederzeit im Menü abrufbar. Nach dem Beenden von Wad oder einem Neustart des Mac sind sie immer leer (siehe 2.4).

### 1.7 Bewusst nicht in Version 1
Unterstützung für Intel-Macs, frei wählbare Taste, Verläufe über einen Neustart hinweg, automatische Updates, großes Einstellungsfenster (Ausnahme: das kleine Fenster für die Fenster-Kürzel, 1.8), Wörterbuch, Textnachbearbeitung durch KI, Bilder im Zwischenablage-Verlauf, Statistiken. Alles kann später kommen, aber nicht jetzt.

### 1.8 Fenstermanager (Etappe 9)
Ein schlanker Fenstermanager im Stil von Spectacle, als eigener, abgeschotteter Baustein. Er teilt sich mit dem Diktieren nur die Menüleiste, nichts sonst.
- **Aktionen:** Vollbild (maximieren, nicht das macOS-Vollbild mit eigenem Schreibtisch), Links, Rechts, Oben, Unten, die vier Viertel und Zentrieren (ohne Größenänderung).
- **Durchschalten:** Wird dasselbe Kürzel mehrmals gedrückt, wechselt die Breite (bei Links/Rechts) bzw. die Höhe (bei Oben/Unten) zwischen ½, ⅔ und ⅓.
- **Fenster-Kürzel …** öffnet ein kleines Fenster mit einer Liste der Aktionen. Klick auf eine Zeile, gewünschte Kombination drücken, fertig. Belegte oder vom System reservierte Kombinationen werden freundlich abgelehnt. Die Kürzel werden in den Einstellungen von Wad gemerkt.
- **Standard-Kürzel (Entscheidung Linus, 19.10.2026):** ⌘⇧F Vollbild, ⌘⇧ + Pfeiltasten für Links, Rechts, Oben, Unten, ⌥⇧ + Pfeiltasten für die Viertel (← oben links, ↑ oben rechts, → unten rechts, ↓ unten links, also im Uhrzeigersinn). Zentrieren: ⌃⌥C (festgelegt beim Bau, weil ⌘⇧C in vielen Apps belegt ist). Linus weiß, dass Text markieren mit ⌘⇧/⌥⇧ + Pfeiltasten in allen Apps nicht mehr geht, solange der Fenstermanager an ist; dafür gibt es den Schalter.
- **Option-Taste:** Die ⌥⇧-Kürzel lösen auch mit der rechten Option-Taste aus. Wird dabei schon eine Aufnahme gestartet, verwirft Wad diese Aufnahme sofort, ohne etwas einzufügen.
- **Vorausschauend:** Fenster bleiben innerhalb von Menüleiste und Dock und auf dem Bildschirm, auf dem sie gerade sind. Apps mit Mindestgröße bekommen, was sie zulassen, ohne Flackern. Fenster im macOS-Vollbild und Fenster, die sich nicht verschieben lassen, werden in Ruhe gelassen.
- **Berechtigung:** keine neue. Fenster werden über die Bedienungshilfen verschoben, die Wad schon hat.

### 1.9 Updates
Wad lädt und installiert nie selbst etwas. Es sagt nur Bescheid, wenn es eine neue Version gibt.
- **Was ist neu:** Startet eine neuere Version zum ersten Mal nach einem Update, zeigt ein kleines Fenster „Wad wurde auf 1.1.0 aktualisiert“ die Stichpunkte aus `WasIstNeu.md` (in der App enthalten) und einen Knopf „Fertig“. Bei einer frischen Installation kommt nichts. Wad merkt sich dafür die zuletzt gestartete Version. Version 1.0.x merkte sich keine; ein Update von dort erkennt Wad an Einstellungen, die nur 1.0.x angelegt haben kann. Im Menü: *Was ist neu …*
- **Standard aus, einmaliger Hinweis** (Entscheidung Linus, 26.10.2026: nur mit ausdrücklicher Einwilligung): Die Update-Prüfung ist ab Werk aus. Beim allerersten Start (frische Installation oder erstes Update auf eine Version mit dieser Funktion) fragt Wad einmal in einem kleinen Fenster: „Immer auf dem neuesten Stand? – Wad kann einmal am Tag nachsehen, ob es eine neue Version gibt. Das ist sinnvoll, damit du Verbesserungen und Fehlerbehebungen bekommst. Dabei fragt Wad bei GitHub nur nach der neuesten Versionsnummer. Diktate, Vokabeln oder Daten über dich werden nie gesendet. Du kannst das jederzeit im Menü ändern oder selbst über „Nach Updates suchen …“ nachsehen.“ Knöpfe *Einschalten* (Standardknopf) und *Nicht jetzt*. Gemerkt wird das als „Update-Frage gezeigt“. Schließen heißt: bleibt aus. Danach kommt der Hinweis nie wieder, auch nicht, wenn man ihn abgelehnt hat. Wer schon im Menü gewählt hat, sieht ihn nicht. Beide Fenster kommen nacheinander und nie über einer Berechtigungsfrage; fehlt eine Berechtigung, warten sie bis zum nächsten Start.
- **Menü:** Schalter *Automatisch nach Updates suchen* und *Nach Updates suchen …* (geht auch bei ausgeschaltetem Schalter). Das Ergebnis kommt sichtbar als kleines Systemfenster mit Wads Symbol und *OK*, nicht als Zeile im Menü (Ergänzung vom 26.10.2026 auf Linus' Wunsch): „Keine Updates gefunden – Wad 1.1.0 ist die neueste Version.“ oder „Keine Verbindung – Wad konnte gerade nicht nachsehen. Versuch es später noch einmal.“ Eine neue Version öffnet gleich ihr Update-Fenster. Die automatische Prüfung bleibt still.
- **Wann:** nur wenn eingeschaltet, frühestens 60 Sekunden nach dem Start, danach höchstens einmal in 24 Stunden. Jeder Versuch zählt, auch ein fehlgeschlagener. Nie während einer Aufnahme, dann ein paar Minuten später. Fehler bei der automatischen Prüfung bleiben still.
- **Neue Version gefunden:** einmal pro Version ein kleines Wad-Fenster (keine macOS-Mitteilung), das der App, in der man gerade schreibt, nicht den Fokus nimmt: „Wad 1.1.1 ist da“, die Beschreibung der Version als schlichter Text (kein HTML, Links nicht anklickbar), Knöpfe *Zum Download* (öffnet https://linushundt.com/wad/download/ im Browser), *Später* und *Diese Version überspringen*. Danach steht oben im Menü „Update verfügbar: 1.1.1 …“, ein Klick öffnet dasselbe Fenster. Überspringen entfernt die Zeile, bis eine noch neuere Version erscheint.
- **Veröffentlichen:** Wad liest die neueste Version auf GitHub (Releases). Die Versionsnummer steht im Tag, etwa `v1.1.1`, die Beschreibung des Release erscheint im Fenster. Vorabversionen wie `1.2.0-beta` bietet Wad nie an.

### 1.10 Vorschau-Fenster
Im Modus *Zwischenablage mit Vorschau* und bei jedem freien Diktieren (3c).
- **Aussehen und Ort:** kleines Fenster im Apple-Stil, 360 Punkte breit, hängt mittig unter Wads Symbol (sonst oben rechts). Es liegt über allem, auf jedem Schreibtisch und über Vollbild-Apps, und nimmt der aktiven App nicht den Fokus.
- **Erscheinen:** erst nach 0,3 s Aufnahme, damit beim Antippen nichts aufblitzt.
- **Text:** Fertiger Text erscheint normal, vorläufiger Text grau. Etwa alle 1,5 Sekunden wandelt Wad den offenen Teil probeweise um; ist das Modell beschäftigt, wird dieser Durchgang übersprungen. In die Zwischenablage kommt nur der endgültige Text.
- **Größe:** Der Textbereich ist mindestens drei bis vier Zeilen hoch und wächst bis etwa 13 Zeilen, danach scrollt er ans Ende.
- **Nach dem Loslassen:** Das Fenster bleibt offen, der Text liegt automatisch in der Zwischenablage, der Knopf zeigt kurz „Kopiert ✓“.
- **Bedienung:** oben links ein X, unten „In Zwischenablage kopieren“. Während des Diktats lässt sich der Text nur markieren. Ist das Diktat fertig, kann man ihn im Fenster korrigieren (Klick hinein, Wad wird dabei nicht zur aktiven App). Der Knopf kopiert dann den korrigierten Text, jede Korrektur setzt „Kopiert ✓“ zurück. Unter „Letzte Diktate“ bleibt der ursprüngliche Text. Schließen oder ein neues Diktat verwirft die Korrekturen.
- **Schließen:** bei anderem Modus, bei ausgeschaltetem Diktieren und wenn kein Text herauskam.
- **Datenschutz:** keine Berechtigung nötig, der Text liegt nur im Arbeitsspeicher.

---

## Teil 2 – Harte Einschränkungen für Sicherheit und Datenschutz

Diese Regeln sind nicht verhandelbar. Jede Etappe muss sie einhalten.

### 2.1 Tastatur: nur die eine Taste
- Wad beobachtet **ausschließlich Änderungen der Sondertasten** (macOS-Ereignistyp `flagsChanged`). Normale Tastenanschläge (`keyDown`/`keyUp`) werden technisch nie abonniert, Wad sieht also nie, welche Buchstaben getippt werden.
- Ausgewertet wird davon nur die **rechte Option-Taste** (Tastencode 61). Alles andere wird sofort verworfen, nichts davon wird gespeichert oder protokolliert.
- Das Erkennen von Cmd+C für den Zwischenablage-Verlauf geschieht **nicht** über die Tastatur, sondern indem Wad den Änderungszähler der Zwischenablage beobachtet.
- Feste Tastenkürzel (⌃⌥W für Vokabeln, die Fenster-Kürzel aus 1.8) werden einzeln beim System angemeldet (`RegisterEventHotKey`). macOS meldet Wad dann nur genau diese Kombinationen, Wad sieht weiterhin keine anderen Tastenanschläge. Deshalb kann ein Kürzel nicht zwischen linker und rechter Option-Taste unterscheiden.

### 2.2 Mikrofon: nur solange die Taste gedrückt ist
- Das Mikrofon wird beim Drücken gestartet und beim Loslassen **vollständig gestoppt** (Audio-Engine aus, nicht nur pausiert). Der orange Mikrofon-Punkt von macOS muss sofort verschwinden. Das ist die sichtbare Kontrolle durch das Betriebssystem selbst.
- Mehrfache Absicherung gegen „Aufnahme läuft weiter“:
  1. **Gegenprüfung:** Während der Aufnahme fragt Wad mehrmals pro Sekunde direkt beim System nach, ob die Taste wirklich noch gedrückt ist. Ist sie es nicht, wird sofort gestoppt, auch wenn das Loslassen-Ereignis verloren ging.
  1a. **Kein falsches Ende (1.0.2):** Ein „losgelassen“ zählt nur, wenn das System die Taste auch oben sieht. Ändert sich das Audiogerät, läuft die Aufnahme auf dem neuen weiter. Während der Aufnahme bleibt der Bildschirm an. Endet eine Aufnahme ungewollt, geht nichts verloren: Das Gesagte wird eingefügt, bei Sperre, Ruhezustand und Benutzerwechsel landet es stattdessen unter „Letzte Diktate“. Eine Meldung mit Ton nennt den Grund, etwa „Aufnahme gestoppt, weil der Bildschirm gesperrt wurde“.
  2. **Zeitlimit:** Eine Aufnahme endet hart nach spätestens 10 Minuten. Dieses Limit ist eine feste Konstante im Code, keine Einstellung.
  3. **Systemereignisse:** Ruhezustand, Bildschirmsperre, Benutzerwechsel, Ausschalten der App oder Entzug einer Berechtigung beenden die Aufnahme sofort.
  4. **Ein Zustand, eine Stelle:** Der Aufnahmezustand wird von genau einer Komponente verwaltet (Zustandsautomat: *bereit → nimmt auf → verarbeitet → bereit*). Es gibt keinen zweiten Weg, das Mikrofon zu starten.
  5. **Ein Prozess:** Wad besteht aus genau einem Programm, ohne Hilfsprozesse oder Terminal-Skripte. Stürzt Wad ab oder wird beendet, schaltet macOS das Mikrofon automatisch ab. Ein „verwaister“ Aufnahmeprozess wie in der alten Version ist damit technisch ausgeschlossen.
- Für diese Absicherungen gibt es automatisierte Tests, insbesondere für den Fall „Loslassen-Ereignis geht verloren“ und „Zeitlimit erreicht“.
- Eine stundenlange Aufnahme darf es unter keinen Umständen geben. Diese Regel hat Vorrang vor jeder anderen Anforderung.

### 2.3 Audio wird nie gespeichert
- Audio existiert **nur im Arbeitsspeicher**. Es wird nie eine Audiodatei geschrieben, auch keine temporäre.
- Jedes Audiostück wird direkt nach seiner Umwandlung mit Nullen überschrieben und freigegeben. Nach dem Diktat existiert kein Audio mehr.
- Zwischenstände (Text einzelner Stücke) werden nach dem Einfügen des Diktats verworfen. Übrig bleibt nur der fertige Text im Diktat-Verlauf.

### 2.4 Verläufe: klarer Ort, sauberes Löschen
- Beide Verläufe liegen **nur im Arbeitsspeicher** von Wad. Es wird keine Verlaufsdatei geschrieben. Damit gibt es auf der Festplatte **keinen einzigen Ort** mit Diktaten oder Zwischenablage-Inhalten.
  - Begründung: Auf SSDs kann man Dateien technisch nicht garantiert „unwiederbringlich“ löschen. Was nie auf die Platte geschrieben wird, muss auch nicht gelöscht werden.
- Beim Löschen werden die Texte vor dem Freigeben mit Nullen überschrieben, soweit Swift das zuverlässig erlaubt. Wo das nicht garantiert ist, steht es ehrlich im Code-Kommentar.
- Wie das genau funktioniert, erklärt der Abschnitt „Wo liegen die Daten?“ am Ende dieses Teils. Dieselbe Erklärung kommt in die README.
- Maximal 20 Einträge je Verlauf. Kommt ein 21. dazu, wird der älteste sofort entfernt.
- *Diktate löschen* und *Verlauf löschen* entfernen alle Einträge sofort.
- Inhalte, die von Passwort-Managern als vertraulich markiert sind (`org.nspasteboard.ConcealedType` / `TransientType`), werden **nie** in den Verlauf aufgenommen.

### 2.5 Zwischenablage beim Einfügen
- Vor dem Einfügen sichert Wad den **kompletten** Inhalt der Zwischenablage (alle Formate, auch Bilder und Dateien).
- Dann legt Wad den diktierten Text hinein, löst Cmd+V aus und stellt danach den vorherigen Inhalt wieder her.
- Der kurzzeitige Diktat-Text wird als „vorübergehend“ markiert, damit er weder im eigenen Verlauf noch in fremden Zwischenablage-Programmen landet.
- Hat der Nutzer in der Zwischenzeit selbst etwas kopiert, wird nichts überschrieben.
- Ergebnis: Für den Nutzer sieht es so aus, als hätte Wad die Zwischenablage nie benutzt.
- Gilt für die Modi *Während* und *Nach dem Diktat*. In den Zwischenablage-Modi soll der Text gerade bleiben.

### 2.6 Netzwerk: genau eine Anfrage
- Der einzige Netzwerkcode steht in `UpdateChecker.swift` und läuft nur, wenn die Update-Prüfung an ist oder man im Menü *Nach Updates suchen …* wählt. Sonst gilt weiter: keine Analyse, keine Absturzberichte, kein Nachladen von Modellen.
- Genau eine Anfrage: `GET https://api.github.com/repos/passauf-unterstrich/wad/releases/latest`. Nur HTTPS, ohne Cookies und ohne Zwischenspeicher (flüchtige Sitzung), 10 Sekunden Zeitlimit, Kennung „Wad/<Version>“. Die Antwort wird nach 256 KB abgebrochen, gelesen werden nur Versionsnummer und Beschreibung.
- Gesendet wird nichts über Diktate, Vokabeln, Einstellungen oder den Nutzer. GitHub sieht, wie bei jedem Aufruf einer Website, die IP-Adresse und die Uhrzeit.
- Wad lädt nie etwas herunter und installiert nichts. *Zum Download* öffnet nur die Seite im Browser.

### 2.7 Berechtigungen
Wad braucht genau zwei Berechtigungen und fragt sie beim ersten Start mit einer kurzen Erklärung ab:
- **Mikrofon** – für die Aufnahme.
- **Bedienungshilfen** – um die Option-Taste zu erkennen, Cmd+V auszulösen und (Etappe 9) Fenster zu verschieben.

Mehr nicht. Wad ist eine eigene, signierte App, sodass nie dem Terminal oder Python Rechte gegeben werden müssen.

### 2.8 Technischer Rahmen
- Swift und SwiftUI, eine native macOS-App, gebaut mit Xcode. Kein Python, kein Electron.
- Einzige fremde Bibliothek: whisper.cpp (inklusive dessen eingebauter Sprach-Erkennung für Pausen).
- Mindestversion: macOS 14 (Sonoma).
- Prozessor: **nur Apple Silicon (M1 und neuer).** Damit Wad auf einem Intel-Mac trotzdem eine freundliche Meldung zeigen kann statt einer unverständlichen Systemfehlermeldung, wird Wad als „Universal“-App gebaut. Auf Intel macht der Intel-Teil nur eines: den Hinweis „Wad braucht einen Mac mit M1-Chip oder neuer“ anzeigen und sich beenden. Mikrofon, Taste und Modell werden dort nie gestartet.
- Keine Protokolle mit Inhalten: Log-Ausgaben enthalten nie Diktat-Text, Zwischenablage-Inhalte oder Audio.

### Wo liegen die Daten? (Erklärung für Linus)

**Was ist der Arbeitsspeicher?** Der Mac hat zwei Arten von Speicher. Die *Festplatte* (SSD) ist das, was du im Finder siehst: Dateien und Ordner, die einen Neustart überstehen. Der *Arbeitsspeicher* (RAM) ist ein separater, flüchtiger Speicher, den jedes laufende Programm als Notizblock benutzt. Er hat keine Dateien und keine Ordner und taucht deshalb **nirgends im Finder** auf. Was dort liegt, verschwindet, sobald das Programm beendet wird, und spätestens beim Ausschalten des Mac, weil der Arbeitsspeicher ohne Strom nichts behält.

**Wer kann darauf zugreifen?** macOS gibt jedem Programm seinen eigenen, abgeschotteten Bereich im Arbeitsspeicher. Andere Programme können ihn nicht lesen. Nur Wad selbst sieht seine Verläufe.

**Wie Wad die Daten benutzt:**
- **Anzeigen im Menü:** Die Verläufe sind zwei Listen mit je höchstens 20 Texten im Arbeitsspeicher. Beim Öffnen des Menüs liest Wad diese Listen und zeigt die Einträge an.
- **Klick auf einen Eintrag:** Wad legt diesen Text in die Zwischenablage von macOS. Ab da liegt er dort wie jeder andere kopierte Text, bis du etwas Neues kopierst.
- **An das Modell geben:** Das Mikrofon liefert die Aufnahme als Zahlenreihe direkt in den Arbeitsspeicher von Wad. Das Modell läuft im selben Programm und liest diese Zahlen von dort. Es entsteht keine Datei, und nichts verlässt den Mac. Nach der Umwandlung wird das Audio überschrieben und freigegeben.
- **Beenden oder Neustart:** Wad schreibt beim Beenden nichts weg. Der Bereich im Arbeitsspeicher wird von macOS zurückgenommen, die Verläufe sind weg. Beim nächsten Start beginnt Wad mit leeren Listen.

**Zwei ehrliche Grenzen:**
- Wenn der Arbeitsspeicher knapp wird, lagert macOS selten genutzte Teile vorübergehend in eine Auslagerungsdatei auf der Festplatte aus. Diese ist von macOS verschlüsselt, wird beim Neustart verworfen und ist für Programme und den Finder nicht lesbar. Wad kann das nicht vollständig verhindern; die Datenmenge ist aber winzig und bleibt geschützt.
- Text, den Wad in eine andere App einfügt (z. B. Notizen oder WhatsApp), speichert natürlich diese App. Das liegt außerhalb von Wad.

---

## Teil 3 – Ablaufplan in Etappen

Jede Etappe endet mit etwas, das Linus selbst ausprobieren kann. Erst nach seiner Freigabe geht es weiter.

| # | Etappe | Was danach funktioniert | So testet Linus es |
|---|--------|------------------------|--------------------|
| 0 | **Gerüst** | Xcode-Projekt, Mikrofon-Symbol in der Menüleiste, Menü mit *An/Aus* und *Beenden*. | App starten, Symbol erscheint, Menü öffnet sich. |
| 1 | **Die Taste** | Rechte Option-Taste wird erkannt (nur `flagsChanged`). Symbol wird beim Drücken rot. Noch keine Aufnahme. | Taste halten, Symbol wird rot, loslassen, wieder normal. Linke Option-Taste bewirkt nichts. |
| 2 | **Sichere Aufnahme** | Mikrofon läuft nur beim Drücken, Audio nur im Speicher, alle Absicherungen aus 2.2 inklusive Tests. | Orange Punkt erscheint und verschwindet sofort. Im Finder ist nirgends eine Audiodatei zu finden. |
| 3 | **Umwandlung** | whisper.cpp mit eingebautem Modell. Modus *Am Ende einfügen*: Text erscheint nach dem Loslassen im Menü (noch kein Einfügen). | Etwas sagen, loslassen, Text im Menü prüfen. Qualität auf Deutsch bewerten (siehe 1.5). |
| 4 | **Einfügen** | Text wird an der Cursorposition eingefügt, Zwischenablage wird danach wiederhergestellt (2.5). | Bild kopieren, diktieren, Cmd+V drücken: das Bild ist noch da. |
| 5 | **Live-Chunking** | Teilen an Sprechpausen, Stücke werden fortlaufend eingefügt, saubere Übergänge. Wird zum Standard. Hier ggf. Blick in Linus' alten Code. | 2 Minuten am Stück diktieren und Übergänge prüfen. |
| 6 | **Verläufe** | Letzte 20 Diktate und letzte 20 kopierte Texte im Menü, Löschen-Funktionen, Passwort-Filter. | 25 Mal kopieren, nur 20 bleiben. Löschen leert sofort. |
| 7 | **Robustheit** | Alle Fälle aus dem Designprinzip „vorausschauend“ (Teil 0, Punkt 7), Intel-Hinweis, Ruhezustand und Sperre, Feinschliff am Symbol, Tests. | Mac während der Aufnahme sperren: Aufnahme endet. Mikrofon während der Aufnahme wechseln. |
| 8 | **Verteilung** | Signierte App als DMG, README (inklusive „Wo liegen die Daten?“), Lizenz GPL-3.0, Download auf Linus' Website mit Zugangscode. | Ein Freund installiert Wad nach Anleitung und kann diktieren. |
| 9 | **Fenstermanager** | Schalter im Menü, die Aktionen aus 1.8 mit Durchschalten, kleines Fenster für die Kürzel. Eigene Datei, kein Eingriff in Aufnahme oder Einfügen. | Mit jedem Kürzel ein Fenster verschieben, Links dreimal drücken (½, ⅔, ⅓), auf einem zweiten Bildschirm testen, Schalter aus: Kürzel tun nichts mehr und Text markieren geht normal. |
| 10 | **Sprache und Einfügemodi** | Sprachwahl im Menü (Standard Deutsch, 1.5), vier Einfügemodi (1.4) und Vorschau-Fenster (1.10). Wahl bleibt über einen Neustart erhalten. | Deutscher Satz mit englischem Anfang bleibt Deutsch. Neustart behält die Wahl. Bild kopieren, Modus 3, Cmd+V gibt den Text. Vorschau in Safari, im Vollbild und auf einem zweiten Schreibtisch prüfen. |
| 11 | **Updates** | „Was ist neu“ nach einem Update, einmaliger Hinweis auf die Update-Prüfung (Standard aus), Menüpunkte, Hinweisfenster mit Überspringen (1.9). Genau eine Netzwerk-Anfrage (2.6). Vorschau nach dem Diktat korrigierbar (1.10). | Von 1.0.2 auf 1.1.0 aktualisieren: „Was ist neu“, dann der Hinweis. Frische Installation: nur der Hinweis. *Einschalten* setzt den Haken im Menü, *Nicht jetzt* lässt ihn weg; beim nächsten Start kein Hinweis mehr. *Nach Updates suchen …* zeigt „Keine Updates gefunden“, ohne WLAN „Keine Verbindung“. In der Vorschau nach dem Diktat ein Wort ändern und einfügen. |

### Zur Verteilung (Etappe 8)
- **Apple Developer Program:** Bis einschließlich Etappe 7 wird ohne gearbeitet. Linus signiert Wad für sich selbst mit seiner kostenlosen Apple-ID. Ob er das Programm (99 $ pro Jahr) für Etappe 8 holt, entscheidet er dann. Etappe 8 beschreibt beide Wege:
  - **Mit Programm:** Wad wird notarisiert. Freunde öffnen die App ohne Warnmeldung, und die Rechte für Bedienungshilfen bleiben bei Updates erhalten.
  - **Ohne Programm:** Wad wird mit einem festen, selbst erstellten Zertifikat signiert, damit die Rechte bei Updates nicht jedes Mal verloren gehen (vermutlich eine Ursache der Probleme mit der alten Version). Freunde müssen Wad beim ersten Öffnen einmalig unter *Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen* freigeben. Die README erklärt das Schritt für Schritt mit Bildern.
- **Lizenz: GPL-3.0.** Wer Wad weiterverbreitet oder verändert weitergibt, muss es ebenfalls offen und frei lassen. whisper.cpp (MIT) ist damit vereinbar.
- Der Quellcode liegt öffentlich auf GitHub. Der Zugangscode auf der Website schützt nur den bequemen Download, nicht den Code selbst.

### Geplant für 1.1.0
- **Installations-DMG automatisch auswerfen.** Nach dem Installieren bleibt das Laufwerk „Wad“ in der Finder-Seitenleiste hängen. Startet Wad aus dem Programme-Ordner, wirft es dieses Laufwerk selbst aus. Ausgeworfen wird nur, was sicher das Wad-Installationsabbild ist: ein eingebundenes Disk-Image (kein echtes Laufwerk, kein Netzlaufwerk) unter `/Volumes`, das eine `Wad.app` mit derselben Bundle-ID enthält. Alles andere bleibt unberührt. Klappt das Auswerfen nicht (etwa weil ein Finder-Fenster darauf geöffnet ist), passiert nichts weiter, keine Fehlermeldung.
