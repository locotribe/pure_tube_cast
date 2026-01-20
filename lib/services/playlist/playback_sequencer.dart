import 'dart:async';
import '../../services/dlna_service.dart';
import '../../services/youtube_service.dart';
import '../../models/playlist_model.dart';
import '../../models/local_playlist_item.dart';

// 状態変更を通知するためのコールバック型定義
typedef OnStateChanged = void Function();

class PlaybackSequencer {
  final DlnaService _dlnaService = DlnaService();
  final YoutubeService _ytService = YoutubeService();

  Timer? _monitorTimer;
  PlaylistModel? _activePlaylist;
  DlnaDevice? _activeDevice;

  // 状態通知用コールバック
  final OnStateChanged onStateChanged;

  PlaybackSequencer({required this.onStateChanged});

  /// セッション開始（指定したプレイリスト・インデックスから再生）
  Future<void> playSequence(DlnaDevice device, PlaylistModel playlist, int startIndex) async {
    _activeDevice = device;
    _activePlaylist = playlist;

    // 範囲チェック
    if (startIndex < 0 || startIndex >= playlist.items.length) return;

    // 1. 全アイテムの状態リセット
    for (var item in playlist.items) {
      item.isPlaying = false;
      item.isQueued = false;
    }

    // 2. 最初のアイテムを再生
    await _playItem(device, playlist, startIndex);

    // 3. 監視タイマー開始
    _startMonitor();
  }

  /// 監視タイマー停止（セッション終了）
  void stopSession() {
    _monitorTimer?.cancel();
    _monitorTimer = null;

    // 状態クリア
    if (_activePlaylist != null) {
      for (var item in _activePlaylist!.items) {
        item.isPlaying = false;
        item.isQueued = false;
      }
      onStateChanged(); // UI更新通知
    }

    _activePlaylist = null;
    _activeDevice = null;
  }

  /// 特定のアイテムを再生する内部メソッド
  Future<void> _playItem(DlnaDevice device, PlaylistModel playlist, int index) async {
    if (index >= playlist.items.length) return;

    final item = playlist.items[index];

    // URL解決
    if (item.streamUrl == null || DateTime.now().difference(item.lastResolved).inMinutes > 50) {
      final url = await _ytService.getStreamUrl(item.originalUrl);
      if (url != null) {
        item.streamUrl = url;
        item.lastResolved = DateTime.now();
      } else {
        item.hasError = true;
        onStateChanged();
        return; // エラー時はスキップなどの処理が必要だが、一旦停止
      }
    }

    // 再生コマンド送信
    await _dlnaService.playNow(device, item.streamUrl!, item.title, item.thumbnailUrl);

    // 状態更新
    for (var i in playlist.items) i.isPlaying = false;
    item.isPlaying = true;
    item.isQueued = true; // 再生中もQueued扱いでOK（二重送信防止）
    playlist.lastPlayedIndex = index;

    onStateChanged();
  }

  /// 監視ループ開始
  void _startMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_activeDevice == null || _activePlaylist == null) {
        timer.cancel();
        return;
      }
      _monitorPlayback(_activeDevice!, _activePlaylist!);
    });
  }

  /// 監視ロジック本体
  Future<void> _monitorPlayback(DlnaDevice device, PlaylistModel playlist) async {
    try {
      // ステータス取得 (Kodi RPC)
      final status = await _dlnaService.getPlayerStatus(device);
      if (status.isEmpty) return; // 再生していない

      // 現在の再生位置など
      final time = _parseTime(status['time']);
      final totalTime = _parseTime(status['totaltime']);
      final percentage = status['percentage'] as double? ?? 0.0;

      // 次の曲の自動キューイング判定 (終了15秒前 or 95%以上)
      bool nearEnd = false;
      if (totalTime > 0 && (totalTime - time) < 15) nearEnd = true;
      if (percentage > 95.0) nearEnd = true;

      if (nearEnd) {
        _processQueue(device, playlist);
      }

    } catch (e) {
      print("[Sequencer] Monitor error: $e");
    }
  }

  /// 次の曲をキューに追加する処理
  Future<void> _processQueue(DlnaDevice device, PlaylistModel playlist) async {
    final currentIndex = playlist.lastPlayedIndex;
    final nextIndex = currentIndex + 1;

    // リスト末尾なら何もしない
    if (nextIndex >= playlist.items.length) return;

    final nextItem = playlist.items[nextIndex];

    // 既にキュー送信済みならスキップ
    if (nextItem.isQueued) return;

    print("[Sequencer] Queueing next item: ${nextItem.title}");
    nextItem.isQueued = true; // 送信開始フラグ
    onStateChanged();

    // URL解決
    if (nextItem.streamUrl == null || DateTime.now().difference(nextItem.lastResolved).inMinutes > 50) {
      final url = await _ytService.getStreamUrl(nextItem.originalUrl);
      if (url != null) {
        nextItem.streamUrl = url;
        nextItem.lastResolved = DateTime.now();
      } else {
        nextItem.hasError = true; // 解決失敗
        // エラーでもisQueuedはtrueのままにして再試行を防ぐ（あるいはエラー処理）
        onStateChanged();
        return;
      }
    }

    // KodiへInsert (現在の再生位置の次に追加)
    // プレイリスト上のインデックス計算が必要だが、簡易的に「末尾追加」ではなく「割り込み」を使う場合
    // KodiのプレイリストIDとこちらのIDがズレる可能性があるため、シンプルな addToPlaylist を使うか検討。
    // 元のコードでは insertToPlaylist を使っていたようなのでそれに倣う。
    // ただしKodi側のプレイリスト位置は "current + 1" が安全。

    // 現在のKodi側インデックスを取得できればベストだが、ここではシンプルに「Add（末尾追加）」または「Insert」
    // 安全策として `addToPlaylist` (末尾追加) を使用するパターンが多いが、
    // ここでは `insertToPlaylist` を使い、位置を `currentIndex + 1` (Kodi上も0始まりなら1曲目は0) と仮定する。
    // ※KodiのPlaylist APIは絶対位置指定。現在再生中が `pos` なら `pos+1` に挿入したい。

    try {
      final status = await _dlnaService.getPlayerStatus(device);
      final currentKodiPos = status['position'] as int? ?? -1;

      if (currentKodiPos != -1) {
        await _dlnaService.insertToPlaylist(
            device,
            currentKodiPos + 1,
            nextItem.streamUrl!,
            nextItem.title,
            nextItem.thumbnailUrl
        );

        // UI更新: 次の曲が再生されるまで「再生中」マークは移動させないが、
        // 実際に再生が切り替わったことを検知するロジックが別途必要。
        // 簡易実装として、ここでは「キュー送信済み」だけマークする。
      }
    } catch(e) {
      print("[Sequencer] Queue error: $e");
      nextItem.isQueued = false; // 失敗したらリトライさせる
    }

    onStateChanged();
  }

  // 時間変換ヘルパー
  int _parseTime(dynamic timeObj) {
    if (timeObj is Map) {
      final h = timeObj['hours'] as int? ?? 0;
      final m = timeObj['minutes'] as int? ?? 0;
      final s = timeObj['seconds'] as int? ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 0;
  }
}