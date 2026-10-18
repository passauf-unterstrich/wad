// Log.swift
// Wads einziges Protokoll: nur Zustandswechsel, nie Diktat-Text, Zwischenablage oder Audio (SPEC 2.8).
// Lesbar mit: log show --predicate 'subsystem == "com.linushundt.Wad"'

import os

let log = Logger(subsystem: "com.linushundt.Wad", category: "Zustand")
