///To store datas of VPN Connection's status detail
class VpnStatus {
  VpnStatus({
    this.packetsOut,
    this.byteIn, 
    this.duration,
    this.byteOut,
    this.connectedOn,
    this.packetsIn,
  });

  ///Packets out byte usages
  final String? packetsOut;

  ///Download byte usages  
  final String? byteIn;

  ///Duration of vpn usage
  final String? duration;

  ///Upload byte usages
  final String? byteOut;

  ///Latest connection date
  ///Return null if vpn disconnected
  final DateTime? connectedOn;

  ///Packets in byte usages
  final String? packetsIn;

  ///Convert to JSON
  Map<String, dynamic> toJson() => {
        "packets_out": packetsOut,
        "byte_in": byteIn,
        "duration": duration,
        "byte_out": byteOut,
        "connected_on": connectedOn,
        "packets_in": packetsIn,
      };

  /// VPNStatus as empty data
  factory VpnStatus.empty() => VpnStatus(
        packetsOut: "0",
        byteIn: "0",
        duration: "00:00:00",
        byteOut: "0",
        connectedOn: null,
        packetsIn: "0",
      );

  @override 
  String toString() => toJson().toString();
}
