import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LiveMapViewer extends StatefulWidget {
  final String sessionId;
  const LiveMapViewer({super.key, required this.sessionId});

  @override
  State<LiveMapViewer> createState() => _LiveMapViewerState();
}

class _LiveMapViewerState extends State<LiveMapViewer> {
  GoogleMapController? _controller;
  final List<LatLng> _path = []; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Seguimiento en Vivo")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('active_locations')
            .doc(widget.sessionId)
            .snapshots(),
        builder: (context, snapshot) {
          
          // 1. SI NO HAY DATOS DE FIREBASE AÚN
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Esperando primera coordenada..."),
                ],
              ),
            );
          }

          // 2. EXTRAER DATOS REALES
          var data = snapshot.data!.data() as Map<String, dynamic>;
          double lat = (data['latitude'] ?? 0.0).toDouble();
          double lng = (data['longitude'] ?? 0.0).toDouble();
          double heading = (data['heading'] ?? 0.0).toDouble();

          // Si las coordenadas son 0,0, es que algo falló en el guardado
          if (lat == 0 && lng == 0) {
            return const Center(child: Text("Coordenadas inválidas (0,0)"));
          }

          LatLng position = LatLng(lat, lng);

          // 3. ACTUALIZAR RASTRO
          if (_path.isEmpty || _path.last != position) {
             _path.add(position);
             if (_path.length > 200) _path.removeAt(0);
          }

          // 4. MOVER CÁMARA (CRUCIAL)
          // Usamos addPostFrameCallback para asegurar que el movimiento
          // ocurra DESPUÉS de que Flutter termine de dibujar este frame.
          if (_controller != null) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
                _controller?.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: position,
                      zoom: 18, // Zoom bien cerca para ver el movimiento
                      tilt: 45, // Inclinación para ver mejor la ruta
                      bearing: heading,
                    ),
                  ),
                );
             });
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: position, zoom: 18),
                onMapCreated: (controller) => _controller = controller,
                markers: {
                  Marker(
                    markerId: const MarkerId('repartidor'),
                    position: position,
                    rotation: heading,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                    infoWindow: InfoWindow(
                      title: "Repartidor",
                      snippet: "$lat, $lng", // ¡Verás los números en el mapa!
                    ),
                    anchor: const Offset(0.5, 0.5),
                  ),
                },
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _path,
                    color: Colors.blueAccent,
                    width: 5,
                  ),
                },
                myLocationEnabled: false,
                zoomControlsEnabled: true,
              ),
              
              // 5. PANEL DE DIAGNÓSTICO (ARRIBA)
              // Esto te mostrará qué coordenadas está recibiendo la app realmente
              Positioned(
                top: 10, left: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Text(
                    "RECIBIDO: $lat, $lng\nVELOCIDAD: ${data['speed'] ?? 0} m/s",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}