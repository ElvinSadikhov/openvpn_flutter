// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'model/vpn_settings_status.dart';
import 'model/vpn_status.dart';

///Stages of vpn connections
enum VPNStage {
  tcp_connect,
  authentication,
  resolve,
  disconnecting,
  vpn_generate_config,
  connecting,
  wait_connection,
  authenticating,
  assign_ip,
  prepare,
  disconnected,
  get_config,
  denied,
  connected,
  udp_connect,
  error,
  exiting,
  unknown,
}

/// Add typedefs at the top
typedef VpnStatusCallback = void Function(VpnStatus? data);
typedef VpnStageCallback = void Function(VPNStage stage, String rawStage);
typedef LastStatusCallback = void Function(VpnStatus status);
typedef LastStageCallback = void Function(VPNStage stage);

class SkVPN {
  ///Channel's names of _vpnStageSnapshot
  static const String _eventChannelVpnStage =
      "id.laskarmedia.openvpn_flutter/vpnstage";

  ///Channel's names of _channelControl
  static const String _methodChannelVpnControl =
      "id.laskarmedia.openvpn_flutter/vpncontrol";

  ///Channel's names of _vpnStageSnapshot
  static const String _eventChannelVpnStageIos =
      "id.laskarmedia.skvpn_flutter/vpnstage";

  ///Channel's names of _channelControl
  static const String _methodChannelVpnControlIos =
      "id.laskarmedia.skvpn_flutter/vpncontrol";

  ///Method channel to invoke methods from native side
  static final MethodChannel _channelControl =
      MethodChannel(Platform.isAndroid ? _methodChannelVpnControl : _methodChannelVpnControlIos);

  ///Snapshot of stream that produced by native side
  static Stream<String> _vpnStageSnapshot() =>
      EventChannel(Platform.isAndroid ? _eventChannelVpnStage : _eventChannelVpnStageIos).receiveBroadcastStream().cast();

  ///Timer to get vpnstatus as a loop
  ///
  ///I know it was bad practice, but this is the only way to avoid android status duration having long delay
  Timer? _vpnStatusTimer;

  ///To indicate the engine already initialize
  bool initialized = false;

  ///Use tempDateTime to countdown, especially on android that has delays
  DateTime? _tempDateTime;

  VPNStage? _lastStage;

  /// is a listener to see vpn status detail
  final VpnStatusCallback? onVpnStatusChanged;

  /// is a listener to see what stage the connection was
  final VpnStageCallback? onVpnStageChanged;

  /// SkiprVPNAdapter's Constructions, don't forget to implement the listeners
  /// onVpnStatusChanged is a listener to see vpn status detail
  /// onVpnStageChanged is a listener to see what stage the connection was
  SkVPN({
    this.onVpnStageChanged,
    this.onVpnStatusChanged,
  });

  ///This function should be called before any usage of SkiprVPNAdapter
  ///All params required for iOS, make sure you read the plugin's documentation
  ///
  ///
  ///providerBundleIdentfier is for your Network Extension identifier
  ///
  ///localizedDescription is for description to show in user's settings
  ///
  ///
  ///Will return latest VPNStage
  Future<void> initialize({
    Function(VPNStage stage)? lastStage,
    Function(VpnStatus status)? lastStatus,
    String? providerBundleIdentifier,
    String? groupIdentifier,
    String? localizedDescription,
  }) async {
    if (Platform.isIOS) {
      assert(
          groupIdentifier != null &&
              providerBundleIdentifier != null &&
              localizedDescription != null,
          "These values are required for ios.");
    }
    onVpnStatusChanged?.call(VpnStatus.empty());
    initialized = true;
    _initializeListener();
    return _channelControl.invokeMethod("initialize", {
      "groupIdentifier": groupIdentifier,
      "providerBundleIdentifier": providerBundleIdentifier,
      "localizedDescription": localizedDescription,
    }).then((value) {
      Future.wait([
        status().then((value) => lastStatus?.call(value)),
        stage().then((value) {
          if (value == VPNStage.connected && _vpnStatusTimer == null) {
            _createTimer();
          }
          return lastStage?.call(value);
        }),
      ]);
    });
  }

  ///Connect to VPN
  ///
  ///config : Your skvpn configuration script, you can find it inside your .ovpn file
  ///
  ///name : name that will show in user's notification
  ///
  ///certIsRequired : default is false, if your config file has cert, set it to true
  ///
  ///username & password : set your username and password if your config file has auth-user-pass
  ///
  ///bypassPackages : exclude some apps to access/use the VPN Connection, it was List<String> of applications package's name (Android Only)
  Future connect(
    String config,
    String name, {
    List<String>? bypassPackages,
    String? username,
    bool certIsRequired = false,
    String? password,
    String? serverAddress,
    bool? isNonGoogleDevice,
  }) {
    if (!initialized) throw ("SkVPN need to be initialized");
    if (!certIsRequired) config += "client-cert-not-required";
    _tempDateTime = DateTime.now();

    try {
      return _channelControl.invokeMethod("connect", {
        "username": username,
        "name": name,
        "is_non_google_device": isNonGoogleDevice ?? false,
        "password": password,
        "config": config,
        "bypass_packages": bypassPackages ?? [],
        "server_address": serverAddress,
      });
    } on PlatformException catch (e) {
      throw ArgumentError(e.message);
    }
  }

  ///Disconnect from VPN
  void disconnect() {
    _tempDateTime = null;
    _channelControl.invokeMethod("disconnect");
    if (_vpnStatusTimer?.isActive ?? false) {
      _vpnStatusTimer?.cancel();
      _vpnStatusTimer = null;
    }
  }

  Future<VpnSettingsStatus?> getVpnSettingsStatus() async {
    try {
      final Map<dynamic, dynamic> result = await _channelControl.invokeMethod('getVpnSettingsStatus');
      return VpnSettingsStatus(
        isAlwaysOn: result['isAlwaysOn'] as bool?,
        isLockdownEnabled: result['isLockdownEnabled'] as bool?,
      );
    } catch (e) {
      print('Failed to get VPN status: $e');
      return null;
    }
  }

  ///Check if connected to vpn
  Future<bool> isConnected() async =>
      stage().then((value) => value == VPNStage.connected);

  ///Get latest connection stage
  Future<VPNStage> stage() async {
    String? stage = await _channelControl.invokeMethod("stage");
    return _strToStage(stage ?? "disconnected");
  }

  ///Get latest connection status
  Future<VpnStatus> status() {
    //Have to check if user already connected to get real data
    return stage().then((value) async {
      var status = VpnStatus.empty();
      if (value == VPNStage.connected) {
        status = await _channelControl.invokeMethod("status").then(_onStatusResult);
      }
      return status;
    });
  }

  FutureOr<VpnStatus> _onStatusResult(value) {
    if (value == null) return VpnStatus.empty();
  
    switch (Platform.operatingSystem) {
      case 'ios':
        var splitted = value.split("_");
        var connectedOn = DateTime.tryParse(splitted[0]);
        if (connectedOn == null) return VpnStatus.empty();
        return VpnStatus(
          connectedOn: connectedOn,
          duration: _duration(DateTime.now().difference(connectedOn).abs()),
          packetsIn: splitted[1],
          packetsOut: splitted[2],
          byteIn: splitted[3],
          byteOut: splitted[4],
        );
      case 'android':
        var data = jsonDecode(value);
        var connectedOn =
            DateTime.tryParse(data["connected_on"].toString()) ??
                _tempDateTime ??
                DateTime.now();
        String byteIn =
            data["byte_in"] != null ? data["byte_in"].toString() : "0";
        String byteOut =
            data["byte_out"] != null ? data["byte_out"].toString() : "0";
        if (byteIn.trim().isEmpty) byteIn = "0";
        if (byteOut.trim().isEmpty) byteOut = "0";
        return VpnStatus(
          connectedOn: connectedOn,
          duration: _duration(DateTime.now().difference(connectedOn).abs()),
          byteIn: byteIn,
          byteOut: byteOut,
          packetsIn: byteIn,
          packetsOut: byteOut,
        );
      default:
        throw Exception("Openvpn not supported on this platform");
    }
  }

  ///Request android permission (Return true if already granted)
  Future<bool> requestPermissionAndroid() async {
    return _channelControl
        .invokeMethod("request_permission")
        .then((value) => value ?? false);
  }

  ///Check android permission [true] if already granted, [false] if not
  Future<bool> checkPermissionAndroid() async {
    return _channelControl
        .invokeMethod("check_permission")
        .then((value) => value ?? false);
  }

  ///Sometimes config script has too many Remotes, it cause ANR in several devices,
  ///This happened because the plugin check every remote and somehow affected the UI to freeze
  ///
  ///Use this function if you wanted to force user to use 1 remote by randomize the remotes provided
  static Future<String?> filteredConfig(String? config) async {
    List<String> remotes = [];
    List<String> output = [];
    if (config == null) return null;
    var raw = config.split("\n");

    for (var item in raw) {
      if (item.trim().toLowerCase().startsWith("remote ")) {
        if (!output.contains("REMOTE_HERE")) {
          output.add("REMOTE_HERE");
        }
        remotes.add(item);
      } else {
        output.add(item);
      }
    }
    String fastestServer = remotes[Random().nextInt(remotes.length - 1)];
    int indexRemote = output.indexWhere((element) => element == "REMOTE_HERE");
    output.removeWhere((element) => element == "REMOTE_HERE");
    output.insert(indexRemote, fastestServer);
    return output.join("\n");
  }

  ///Convert duration that produced by native side as Connection Time
  String _duration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  ///Private function to convert String to VPNStage
  static VPNStage _strToStage(String? stage) {
    if (stage == null ||
        stage.trim().isEmpty ||
        stage.trim() == "idle" ||
        stage.trim() == "invalid") {
      return VPNStage.disconnected;
    }
    var indexStage = VPNStage.values.indexWhere((element) => element
        .toString()
        .trim()
        .toLowerCase()
        .contains(stage.toString().trim().toLowerCase()));
    if (indexStage >= 0) return VPNStage.values[indexStage];
    return VPNStage.unknown;
  }

  ///Initialize listener, called when you start connection and stoped while
  void _initializeListener() {
    _vpnStageSnapshot().listen((event) {
      var vpnStage = _strToStage(event);
      if (vpnStage != _lastStage) {
        onVpnStageChanged?.call(vpnStage, event);
        _lastStage = vpnStage;
      }
      if (vpnStage != VPNStage.disconnected) {
        if (Platform.isAndroid) {
          _createTimer();
        } else if (Platform.isIOS && vpnStage == VPNStage.connected) {
          _createTimer();
        }
      } else {
        _vpnStatusTimer?.cancel();
      }
    });
  }

  ///Create timer to invoke status
  void _createTimer() {
    if (_vpnStatusTimer != null) {
      _vpnStatusTimer!.cancel();
      _vpnStatusTimer = null;
    }
    _vpnStatusTimer ??=
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      onVpnStatusChanged?.call(await status());
    });
  }
}
