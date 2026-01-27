// lib/views/remote_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import '../managers/playlist_manager.dart';

class RemoteView extends StatefulWidget {
  const RemoteView({super.key});

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _playlistManager = PlaylistManager();
  Timer? _statusPollingTimer;

  bool _isConnected = false;
  String _currentTitle = "未接続 / 再生なし";
  String _currentThumbnail = "";

  bool _isPlaying = false;
  bool _hasMedia = false;

  int _currentTime = 0;
  int _totalTime = 1;
  double _currentSpeed = 1.0;
  int _currentVolume = 50;

  bool _isSeeking = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    super.dispose();
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
          // サムネイル補完
          String thumbUrl = status['thumbnail'] ?? "";
          if (thumbUrl.isEmpty || !thumbUrl.startsWith('http')) {
            final playingItem = _findPlayingItem();
            if (playingItem != null && playingItem.thumbnailUrl != null) {
              thumbUrl = playingItem.thumbnailUrl!;
            }
          }

          setState(() {
            _isConnected = true;
            _hasMedia = true;

            _currentTitle = status['title'] != "" ? status['title'] : "再生中";
            _currentThumbnail = thumbUrl;

            if (!_isSeeking) {
              _currentTime = status['time'];
            }
            _totalTime = status['totaltime'] > 0 ? status['totaltime'] : 1;

            double speed = (status['speed'] as num).toDouble();
            _isPlaying = speed != 0;
            if (speed == 0) speed = 1.0;

            _currentSpeed = speed;
            _currentVolume = (status['volume'] as num).toInt();
          });
        } else {
          setState(() {
            _isConnected = true;
            _hasMedia = false;
            _currentTitle = "再生停止中";
            _currentThumbnail = "";
            _isPlaying = false;
          });
        }
      }
    });
  }

  LocalPlaylistItem? _findPlayingItem() {
    for (var playlist in _playlistManager.currentPlaylists) {
      for (var item in playlist.items) {
        if (item.isPlaying) return item;
      }
    }
    return null;
  }

  // --- 操作ロジック ---

  // 【修正】標準的な早送り・巻き戻し機能 (increment / decrement)
  // Kodiの標準挙動として、押すたびに速度が 2x, 4x, 8x... または -2x, -4x... と変化します
  void _fastForwardRewind(bool isForward) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      // DlnaServiceの changeSpeed メソッドを使用 (Player.SetSpeed "increment"/"decrement")
      _dlnaService.changeSpeed(device, isForward ? "increment" : "decrement");

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isForward ? "早送り (速度アップ)" : "巻き戻し (速度ダウン)"),
          duration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  void _resetSpeed() {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.resetSpeed(device);
      setState(() => _currentSpeed = 1.0);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("標準速度 (1.0x)"),
          duration: Duration(milliseconds: 500),
        ),
      );
    }
  }

  // シークバー操作
  void _onSeekStart(double value) {
    setState(() {
      _isSeeking = true;
    });
  }

  void _onSeekUpdate(double value) {
    setState(() {
      _currentTime = value.toInt();
    });
  }

  void _onSeekEnd(double value) {
    setState(() {
      _isSeeking = false;
    });
    final device = _dlnaService.currentDevice;
    if (device != null && _totalTime > 0) {
      double percentage = (value / _totalTime) * 100.0;
      _dlnaService.seekTo(device, percentage);
    }
  }

  // 相対シーク
  void _seekRelative(int seconds) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.seekRelative(device, seconds);
      setState(() {
        _currentTime = (_currentTime + seconds).clamp(0, _totalTime);
      });
    }
  }

  void _skipPrevious() {
    if (!_isConnected || !_hasMedia) return;
    _dlnaService.skipPrevious(_dlnaService.currentDevice!);
  }

  void _skipNext() {
    if (!_isConnected || !_hasMedia) return;
    _dlnaService.skipNext(_dlnaService.currentDevice!);
  }

  void _togglePlayPause() {
    if (!_isConnected || !_hasMedia) return;
    _dlnaService.togglePlayPause(_dlnaService.currentDevice!);
    setState(() => _isPlaying = !_isPlaying);
  }

  String _getKodiImageUrl(String kodiPath) {
    if (kodiPath.isEmpty) return "";
    if (kodiPath.startsWith("http") && !kodiPath.startsWith("image://")) return kodiPath;

    final device = _dlnaService.currentDevice;
    if (device == null) return "";

    return "http://${device.ip}:${device.port}/image/${Uri.encodeComponent(kodiPath)}";
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
        actions: [],
      ),
      body: device == null
          ? const Center(child: Text("デバイスに接続されていません"))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. サムネイル表示エリア
            AspectRatio(
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
                    if (_currentThumbnail.isNotEmpty)
                      Image.network(
                        _getKodiImageUrl(_currentThumbnail),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                      ),

                    Container(color: Colors.black.withOpacity(0.4)),

                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _hasMedia ? "再生中" : "停止中",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _currentTitle,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: _currentSpeed != 1.0 ? Colors.red : Colors.grey.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "Speed: ${_currentSpeed.toStringAsFixed(1)}x",
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 2. シークバー
            Row(
              children: [
                InkWell(
                  onTap: () => _seekRelative(-10),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(Icons.replay_10, color: Colors.grey.withOpacity(0.2), size: 32),
                        Text(formatTime(_currentTime), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: Slider(
                    value: _currentTime.toDouble().clamp(0, _totalTime.toDouble()),
                    min: 0,
                    max: _totalTime.toDouble(),
                    activeColor: controlColor,
                    inactiveColor: Colors.grey.shade300,
                    onChanged: _hasMedia ? _onSeekUpdate : null,
                    onChangeStart: _hasMedia ? _onSeekStart : null,
                    onChangeEnd: _hasMedia ? _onSeekEnd : null,
                  ),
                ),

                InkWell(
                  onTap: () => _seekRelative(10),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(Icons.forward_10, color: Colors.grey.withOpacity(0.2), size: 32),
                        Text(formatTime(_totalTime), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 3. 再生コントロール
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 42,
                  color: iconColor,
                  onPressed: _hasMedia ? _skipPrevious : null,
                ),
                FloatingActionButton(
                  onPressed: _hasMedia ? _togglePlayPause : null,
                  backgroundColor: _hasMedia ? Colors.red : Colors.grey,
                  elevation: 4,
                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 42, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 42,
                  color: iconColor,
                  onPressed: _hasMedia ? _skipNext : null,
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 4. 速度コントロール (単純な早送り・巻き戻しに戻す)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text("速度コントロール", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 巻き戻し
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fast_rewind), // アイコンを戻す
                      iconSize: 36,
                      color: iconColor,
                      onPressed: _hasMedia ? () => _fastForwardRewind(false) : null,
                    ),
                    Text("巻き戻し", style: TextStyle(fontSize: 12, color: iconColor, fontWeight: FontWeight.bold)),
                  ],
                ),

                // 標準に戻す
                ElevatedButton.icon(
                  onPressed: _hasMedia ? _resetSpeed : null,
                  icon: const Icon(Icons.speed, size: 20),
                  label: const Text(
                    "標準 (1.0x)",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),

                // 早送り
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.fast_forward), // アイコンを戻す
                      iconSize: 36,
                      color: iconColor,
                      onPressed: _hasMedia ? () => _fastForwardRewind(true) : null,
                    ),
                    Text("早送り", style: TextStyle(fontSize: 12, color: iconColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 5. 音量スライダー
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