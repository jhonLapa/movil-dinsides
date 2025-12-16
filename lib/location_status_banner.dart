import 'package:flutter/material.dart';

enum LocationStatus { connecting, online, stale, offline }

class LocationStatusBanner extends StatelessWidget {
  final DateTime? lastUpdated;
  final bool isGpsDisabled;

  const LocationStatusBanner({
    Key? key,
    required this.lastUpdated,
    this.isGpsDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    LocationStatus status = _determineStatus();
    if (status == LocationStatus.online) return SizedBox.shrink();

    Color bgColor;
    IconData icon;
    String text;

    switch (status) {
      case LocationStatus.connecting:
        bgColor = Colors.blueAccent;
        icon = Icons.cloud_sync;
        text = "Conectando...";
        break;
      case LocationStatus.stale:
        bgColor = Colors.orange;
        icon = Icons.wifi_off;
        final mins = DateTime.now().difference(lastUpdated!).inMinutes;
        text = "Señal débil. Hace $mins min";
        break;
      case LocationStatus.offline:
        bgColor = Colors.redAccent;
        icon = Icons.location_off;
        text = isGpsDisabled ? "GPS Apagado" : "Sin conexión";
        break;
      default:
        bgColor = Colors.grey; icon = Icons.help; text = "";
    }

    return Positioned(
      top: 60, left: 20, right: 20,
      child: Material(
        elevation: 4, borderRadius: BorderRadius.circular(20), color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Flexible(child: Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }

  LocationStatus _determineStatus() {
    if (isGpsDisabled) return LocationStatus.offline;
    if (lastUpdated == null) return LocationStatus.connecting;
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inSeconds < 60) return LocationStatus.online;
    if (diff.inMinutes < 5) return LocationStatus.stale;
    return LocationStatus.offline;
  }
}