import 'package:http/http.dart' as http;
import '../../models/dlna_device.dart';

class DlnaSoapClient {

  /// 汎用DLNA (UPnP AVTransport) を使用して動画をキャストする
  Future<void> castVideo(DlnaDevice device, String videoUrl, String title) async {
    // URLの構成: http://IP:PORT/ControlURL
    final fullControlUrl = 'http://${device.ip}:${device.port}${device.controlUrl}';

    // 1. SetAVTransportURI (再生するURIを設定)
    await _sendSoap(
        fullControlUrl,
        device.serviceType,
        'SetAVTransportURI',
        {
          'InstanceID': '0',
          'CurrentURI': videoUrl,
          'CurrentURIMetaData': '' // 必要に応じてDIDL-Lite形式のメタデータを生成可能
        }
    );

    // 2. Play (再生開始)
    await _sendSoap(
        fullControlUrl,
        device.serviceType,
        'Play',
        {
          'InstanceID': '0',
          'Speed': '1'
        }
    );
  }

  Future<void> _sendSoap(String url, String serviceType, String action, Map<String, String> args) async {
    // SOAP Bodyの引数部分を作成
    String argsXml = args.entries.map((e) => "<${e.key}>${e.value}</${e.key}>").join();

    // SOAP Envelopeの作成
    String soap = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
<s:Body>
<u:$action xmlns:u="$serviceType">$argsXml</u:$action>
</s:Body>
</s:Envelope>''';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPAction': '"$serviceType#$action"'
        },
        body: soap,
      );

      if (response.statusCode != 200) {
        print("[DlnaSoap] Error: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("[DlnaSoap] Exception: $e");
    }
  }
}