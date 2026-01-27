// lib/views/remote_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dlna_service.dart';
import '../managers/playlist_manager.dart'; // 【追加】リスト情報参照用

class RemoteView extends StatefulWidget {
  const RemoteView({super.key});

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  final DlnaService _dlnaService = DlnaService();
  final PlaylistManager _playlistManager = PlaylistManager(); // 【追加】
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

  // シークバー操作中の競合を防ぐフラグ
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
          // 【追加】リストから再生中のアイテムを探してサムネイルを補完
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
            _currentThumbnail = thumbUrl; // 補完したURLを使用

            // シーク操作中でなければ時間を更新
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

  // 【追加】PlaylistManagerから再生中のアイテムを検索
  LocalPlaylistItem? _findPlayingItem() {
    for (var playlist in _playlistManager.currentPlaylists) {
      for (var item in playlist.items) {
        if (item.isPlaying) return item;
      }
    }
    return null;
  }

  // --- 操作ロジック ---

  void _fastForwardRewind(bool isForward) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      // 【変更】倍速(increment)ではなく、テンポ操作(tempoup/tempodown)を実行
      // これにより、0.1x〜0.25x単位などの細かい速度調整を試みます
      _dlnaService.executeAction(device, isForward ? "tempoup" : "tempodown");
    }
  }

  void _resetSpeed() {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.resetSpeed(device);
      setState(() => _currentSpeed = 1.0);
    }
  }

  // シークバー操作開始
  void _onSeekStart(double value) {
    setState(() {
      _isSeeking = true;
    });
  }

  // シークバー操作中 (UI表示のみ更新)
  void _onSeekUpdate(double value) {
    setState(() {
      _currentTime = value.toInt();
    });
  }

  // シークバー操作終了
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

  // 【追加】相対シーク (10秒送り/戻し用)
  void _seekRelative(int seconds) {
    if (!_isConnected || !_hasMedia) return;
    final device = _dlnaService.currentDevice;
    if (device != null) {
      _dlnaService.seekRelative(device, seconds);
      // UIも一時的に更新して反応を良く見せる
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
    // httpから始まる場合はそのまま（PlaylistManager由来など）
    if (kodiPath.startsWith("http") && !kodiPath.startsWith("image://")) return kodiPath;

    final device = _dlnaService.currentDevice;
    if (device == null) return "";

    // Kodiの画像プロキシ
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
                            if (_currentSpeed != 1.0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Speed: ${_currentSpeed}x",
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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

            // 2. シークバーとタップ可能な時間表示
            Row(
              children: [
                // 左：現在時間（タップで-10秒）
                InkWell(
                  onTap: () => _seekRelative(-10),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 裏側に薄くアイコンを表示
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

                // 右：合計時間（タップで+10秒）
                InkWell(
                  onTap: () => _seekRelative(10),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 裏側に薄くアイコンを表示
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

            // 4. 速度コントロール
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text("再生速度コントロール", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
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
                ElevatedButton.icon(
                  onPressed: _hasMedia ? _resetSpeed : null,
                  icon: const Icon(Icons.speed, size: 18),
                  label: const Text(
                    "標準に戻す",
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