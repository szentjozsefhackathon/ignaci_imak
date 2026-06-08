# Prayer Timer Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DATA FLOW & BUG FIXES                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  PrayerPage.initState()                                              │
│    │                                                                │
│    ├─ preparePrayer(total)                                          │
│    │    _prayerTotal = total                                         │
│    │    _remainingTime = total                                       │
│    │                                                                │
│    ├─ startPrayerTimer()                                            │
│    │    _prayerStartTime = DateTime.now()                           │
│    │    _prayerElapsed = Duration.zero                               │
│    │    _remainingTime = _prayerTotal                                │
│    │    └─ _startPrayerTimer()                                       │
│    │         _prayerIsRunning = true                                 │
│    │         _prayerTimer = Timer.periodic(1s) ──────────┐          │
│    │                                                     │          │
│    └─ playbackState.listen((_) {                         │          │
│           if (_audioHandler.isFinished) → close           │          │
│           if (_audioHandler.prayerIsRunning) → FAB play   │          │
│           else → FAB pause                                 │          │
│           setState(() { _currentPage = ... })              │          │
│           build() → reads remainingTime, prayerIsRunning  │          │
│       })                                                    │          │
│                                                          │          │
│  ═══════ TIMER TICK (every 1s) ══════════════════════════╝          │
│                                                                     │
│  _remainingTime = _prayerTotal - (now - _prayerStartTime!)          │
│  _prayerElapsed = _prayerTotal - _remainingTime                      │
│                                                                     │
│  playbackState.add(copyWith(                                        │
│    updatePosition: _prayerElapsed,    → lock screen progress bar    │
│    playing: _prayerActive && !_paused, → lock screen play/pause     │
│    speed: 1,                                                         │
│  ))                                                                  │
│    │                                                                │
│    ▼  (async delivery via BehaviorSubject)                          │
│  playbackState listener: setState() → build()                       │
│    reads remainingTime → display "Hátralévő idő: MM:SS"              │
│                                                                     │
│                                                                     │
│  ═══════ _transformEvent (player event stream) ═══════════════════════│
│                                                                     │
│  Called by: _player.playbackEventStream.listen(...)                  │
│                                                                     │
│  PlaybackState(                                                      │
│    processingState: ...,                                             │
│    playing: _prayerActive && !_paused,                               │
│    updatePosition: _prayerTotal > 0 ? _prayerElapsed : _player.pos, │
│    bufferedPosition: _player.bufferedPosition,                       │
│    speed: _prayerTotal > 0 ? (_paused ? 0 : 1) : _player.speed,     │
│    queueIndex: _currentIndex,                                        │
│  )                                                                    │
│                                                                     │
│  NOTE: _transformEvent and timer tick now use SAME playing logic    │
│  (_prayerActive && !_paused). No more alternating play/pause.       │
│                                                                     │
│                                                                     │
│  ═══════ loadPrayerVoices() ══════════════════════════════════════════│
│                                                                     │
│  1. _paused = false      ──────────────────────────────────────┐    │
│  2. _prayerElapsed = 0   (reset, but timer recalculates next   │    │
│                            tick from wall-clock → correct)     │    │
│  3. _stopBgLoop()                                             │    │
│  4. Dispose old _player, create new _player, new listener     │    │
│  5. Load voice files from DB → _voiceUris                     │    │
│  6. _isFinished = false                                       │    │
│  7. _prayerActive = true          ◄── enables timer playing    │    │
│  8. _pageStartTimes = computePageStartTimes(...)              │    │
│  9. _totalSteps = steps.length                                │    │
│ 10. playbackState.add(PlaybackState(                          │    │
│       playing: true,                                          │    │
│       updatePosition: _prayerElapsed,  ◄── BUG #3 FIXED       │    │
│       controls: [...]                                         │    │
│     ))                                                        │    │
│ 11. _currentIndex = 0                                        │    │
│ 12. queue.add(mediaItems)                                    │    │
│ 13. _loadAndPlayStep(0) → player starts first step audio     │    │
│ 14. _startBgLoop() → silence loop for iOS lock screen        │    │
│                                                                     │
│                                                                     │
│  ═══════ play() ════════════════════════════════════════════════════╝│
│                                                                     │
│  _paused = false                                                     │
│  If _pausedAt != null: adjust _prayerStartTime by pause duration    │
│  If _prayerTimer == null: _startPrayerTimer()  ◄── BUG #4 FIXED     │
│  playbackState.add(copyWith(playing: true, updatePosition: ...))     │
│  If player.idle/completed: return                                   │
│  else: _player.play()                                               │
│                                                                     │
│                                                                     │
│  ═══════ pause() ════════════════════════════════════════════════════│
│                                                                     │
│  _paused = true                                                     │
│  _pausedAt = DateTime.now()                                         │
│  _prayerTimer?.cancel() / _prayerTimer = null                       │
│  _prayerIsRunning = false                                           │
│  playbackState.add(copyWith(playing: false, updatePosition: ...))   │
│  If _player.playing: _player.pause()                                │
│                                                                     │
│                                                                     │
│  ═══════ skipToQueueItem(index) ══════════════════════════════════════│
│                                                                     │
│  _currentIndex = index                                              │
│  _prayerCurrentPage = index                                         │
│  If index < _pageStartTimes.length:                                 │
│    _remainingTime = _pageStartTimes[index]                           │
│    _prayerStartTime = now - (_prayerTotal - _remainingTime)         │
│    _prayerElapsed = _prayerTotal - _remainingTime                   │
│    ◄── BUG #2 FIXED: timer wall-clock now matches snapped time      │
│  playbackState.add(copyWith(queueIndex: index))                     │
│  mediaItem.add(queue.value[index])                                  │
│  _loadAndPlayStep(index)                                            │
│                                                                     │
│                                                                     │
│  ═══════ finish() / _finishPrayer() ═════════════════════════════════│
│                                                                     │
│  _prayerTimer?.cancel() / _prayerTimer = null                       │
│  _prayerIsRunning = false                                           │
│  _prayerActive = false                                              │
│  _prayerTotal = Duration.zero                                       │
│  _isFinished = true                                                 │
│  _player.stop(), _bgPlayer.stop()                                   │
│  Play csengo.mp3 finish sound                                       │
│                                                                     │
│                                                                     │
│  ═══════ stop() / stopPrayer() ══════════════════════════════════════│
│                                                                     │
│  Cancel timer, reset fields                                         │
│  Stop both players                                                  │
│  Restore DND                                                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Signal Flows

### Lock Screen (iOS Control Center / Android Notification)

```
timer tick → playbackState.add(copyWith(
    updatePosition: _prayerElapsed,    ← progress bar position
    playing: _prayerActive && !_paused ← play/pause icon
    speed: 1,
)) → audio_service plugin → MPNowPlayingInfoCenter (iOS)
```

### Prayer Page UI

```
timer tick → playbackState.add(copyWith(...))
  → BehaviorSubject async delivery
  → playbackState.listen((_) { setState(() { ... }); })
  → build() reads _audioHandler.remainingTime
  → Text("Hátralévő idő: MM:SS")
```

### Auto Page Turn

```
timer tick: _remainingTime = _prayerTotal - (now - _prayerStartTime)
  → if _remainingTime <= _pageStartTimes[nextPage]:
    → skipToQueueItem(nextPage)
      → snap _remainingTime, adjust _prayerStartTime (Bug #2 fixed)
      → _loadAndPlayStep(nextPage)
      → _vibrateIfNoSound()
```

---

## Bug Fixes Summary

| # | Bug | Root Cause | Fix |
|---|-----|-----------|-----|
| 1 | iOS lock screen crash on pause | Timer tick used `playing: !_paused`, `_transformEvent` used `playing: _prayerActive && !_paused`. Before `loadPrayerVoices`, these disagree → rapid alternating play/pause states sent to iOS | `audio_handler.dart:588`: changed to `playing: _prayerActive && !_paused` |
| 2 | Page snap overwritten by wall-clock | `skipToQueueItem` set `_remainingTime = _pageStartTimes[index]`, but next timer tick recalculated from `_prayerTotal - (now - _prayerStartTime!)`, overwriting the snap | `audio_handler.dart:465-467`: adjust `_prayerStartTime` and `_prayerElapsed` to match the snapped remaining time |
| 3 | Lock screen progress bar resets to 0 briefly | `loadPrayerVoices` emitted `PlaybackState(playing: true)` without `updatePosition`, defaulting to `Duration.zero` | `audio_handler.dart:406`: added `updatePosition: _prayerElapsed` |
| 4 | Timer can't restart after early pause | `play()` guard `if (_prayerActive && _prayerTimer == null)` prevented timer restart when `_prayerActive` was still false (before `loadPrayerVoices` completed) | `audio_handler.dart:162`: removed `_prayerActive &&` from guard |
