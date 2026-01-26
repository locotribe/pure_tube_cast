import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';

class RemoteView extends StatefulWidget {
  const RemoteView({super.key});

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  final DlnaService _dlnaService = DlnaService();
  Timer? _statusPollingTimer;

  bool _isConnected = false;
  String _currentTitle = "未接続 / 再生なし";

  bool _isPlaying = false;
  bool _hasMedia = false;

  int _currentTime = 0;
  int _totalTime = 1;
  double _currentSpeed = 1.0;
  int _currentVolume = 50;

  int _skipInterval = 10;

  Timer? _skipDebounceTimer;
  int _accumulatedSkipSeconds = 0;
  bool _isSkipping = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startPolling();
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    _skipDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _skipInterval = prefs.getInt('remote_skip_interval') ?? 10;
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('remote_skip_interval', _skipInterval);
  }

  void _startPolling() {
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final device = _dlnaService.currentDevice;
      if (device == null) {
        if (mounted && _isConnected) setState(() => _isConnected = false);
        return;
      }

      final status = await _dlnaService.getPlayerPropertiesForRemote(device);
      if (mounted) {
        if (status != null) {
          setState(() {
            _isConnected = true;
            _hasMedia = true;

            _currentTitle = status['title'] != "" ? status['title'] : "再生中";
            _currentTime = status['time'];
            _totalTime = status['totaltime'] > 0 ? status['totaltime'] : 1;

            double speed = (status['speed'] as num).toDouble();
            _isPlaying = speed != 0;

            // 停止中は速度0が返るが、表示上は1.0にしておく
            if (speed == 0) speed = 1.0;
            _currentSpeed = speed;
            _currentVolume = (status['volume'] as num).toInt();
          });
        } else {
          setState(() {
            _isConnected = true;
            _hasMedia = false;
            _currentTitle = "再生停止中";
            _isPlaying = false;
          });
        }
      }
    });
  }

  // --- 操作ロジック ---

  void _handleSkip(bool isForward) {
    if (!_isConnected || !_hasMedia) return;

    _skipDebounceTimer?.cancel();

    setState(() {
      _isSkipping = true;
      if (isForward) {
        _accumulatedSkipSeconds += _skipInterval;
      } else {
        _accumulatedSkipSeconds -= _skipInterval;
      }
    });

    _skipDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (_accumulatedSkipSeconds != 0) {
        final device = _dlnaService.currentDevice;
        if (device != null) {
          _dlnaService.seekRelative(device, _accumulatedSkipSeconds);
        }
      }
      if (mounted) {
        setState(() {
          _accumulatedSkipSeconds = 0;
          _isSkipping = false;
        });
      }
    });
  }

  // 早送り・巻き戻し (Increment/Decrement)
  void _fastForwardRewind(bool isForward) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.changeSpeed(device, isForward ? "increment" : "decrement");
    }
  }

  // 速度リセット (1.0x)
  void _resetSpeed() {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.resetSpeed(device);
      // 即座にUIを1.0に戻して反応を良く見せる
      setState(() => _currentSpeed = 1.0);
    }
  }

  // 速度微調整 (TempoUp/Down)
  void _modifyTempo(bool isIncrement) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.changeTempo(device, isIncrement ? "increment" : "decrement");
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBd) {
          return AlertDialog(
            title: const Text("リモコン設定"),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("スキップ秒数"),
                DropdownButton<int>(
                  value: _skipInterval,
                  items: const [3, 5, 10, 15, 30].map((e) => DropdownMenuItem(value: e, child: Text("$e秒"))).toList(),
                  onChanged: (val) {
                    if (val != null) setStateBd(() => _skipInterval = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {});
                  _saveSettings();
                  Navigator.pop(ctx);
                },
                child: const Text("保存"),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UI構築 ---

  @override
  Widget build(BuildContext context) {
    String formatTime(int sec) {
      int m = sec ~/ 60;
      int s = sec % 60;
      return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }

    final device = _dlnaService.currentDevice;
    final Color controlColor = _hasMedia ? Colors.red : Colors.grey;
    final Color iconColor = _hasMedia ? Colors.black87 : Colors.grey.shade300;

    return Scaffold(
      appBar: AppBar(
        title: const Text("リモコン"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: device == null
          ? const Center(child: Text("デバイスに接続されていません"))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ------------------------------------------
            // 1. テレビ画面風タッチパッド (シーク)
            // ------------------------------------------
            Opacity(
              opacity: _hasMedia ? 1.0 : 0.5,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade800, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 情報表示エリア
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSkipping) ...[
                                Text(
                                  _accumulatedSkipSeconds > 0 ? "+${_accumulatedSkipSeconds}s" : "${_accumulatedSkipSeconds}s",
                                  style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                                ),
                                const Text("Seeking...", style: TextStyle(color: Colors.grey)),
                              ] else ...[
                                Text(
                                  _currentTitle,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "${formatTime(_currentTime)} / ${formatTime(_totalTime)}",
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // タップ領域 (左:戻る / 右:進む)
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _hasMedia ? () => _handleSkip(false) : null,
                              splashColor: Colors.white24,
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: const Icon(Icons.replay_10, color: Colors.white24, size: 40),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: _hasMedia ? () => _handleSkip(true) : null,
                              splashColor: Colors.white24,
                              child: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.forward_10, color: Colors.white24, size: 40),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ------------------------------------------
            // 2. 再生コントロール (前・再生・次)
            // ------------------------------------------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 42,
                  color: iconColor,
                  onPressed: _hasMedia ? () => _dlnaService.skipPrevious(device) : null,
                ),
                FloatingActionButton(
                  onPressed: _hasMedia ? () {
                    _dlnaService.togglePlayPause(device);
                    setState(() => _isPlaying = !_isPlaying);
                  } : null,
                  backgroundColor: _hasMedia ? Colors.red : Colors.grey,
                  elevation: 4,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 42, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 42,
                  color: iconColor,
                  onPressed: _hasMedia ? () => _dlnaService.skipNext(device) : null,
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),

            // ------------------------------------------
            // 3. 速度コントロール (メイン)
            // ------------------------------------------
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text("再生速度コントロール", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // [巻き戻し]
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fast_rewind),
                      iconSize: 32,
                      color: iconColor,
                      onPressed: _hasMedia ? () => _fastForwardRewind(false) : null,
                    ),
                    Text("巻き戻し", style: TextStyle(fontSize: 10, color: iconColor)),
                  ],
                ),

                // [リセットボタン (1.0x)]
                ElevatedButton.icon(
                  onPressed: _hasMedia ? _resetSpeed : null,
                  icon: const Icon(Icons.speed, size: 18),
                  label: Text(
                    "1.0x\n標準に戻す",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                  ),
                ),

                // [早送り]
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fast_forward),
                      iconSize: 32,
                      color: iconColor,
                      onPressed: _hasMedia ? () => _fastForwardRewind(true) : null,
                    ),
                    Text("早送り", style: TextStyle(fontSize: 10, color: iconColor)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ------------------------------------------
            // 4. 速度微調整 / スロー (実験的機能)
            // ------------------------------------------
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text("微調整・スロー (現在の速度: ${_currentSpeed}x)",
                      style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _hasMedia ? () => _modifyTempo(false) : null,
                        icon: const Icon(Icons.remove),
                        color: iconColor,
                        tooltip: "速度ダウン",
                      ),

                      // 現在の速度表示 (ただの表示)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white,
                        ),
                        child: Text(
                          "${_currentSpeed}x",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),

                      IconButton(
                        onPressed: _hasMedia ? () => _modifyTempo(true) : null,
                        icon: const Icon(Icons.add),
                        color: iconColor,
                        tooltip: "速度アップ",
                      ),
                    ],
                  ),
                  const Text("※環境により動作しない場合があります", style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // ------------------------------------------
            // 5. 音量スライダー
            // ------------------------------------------
            Row(
              children: [
                Icon(Icons.volume_up, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _currentVolume.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: "$_currentVolume",
                    activeColor: controlColor,
                    onChanged: _hasMedia ? (val) {
                      setState(() => _currentVolume = val.toInt());
                    } : null,
                    onChangeEnd: _hasMedia ? (val) {
                      _dlnaService.setVolume(device, val.toInt());
                    } : null,
                  ),
                ),
                SizedBox(width: 40, child: Text("$_currentVolume", textAlign: TextAlign.end)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}