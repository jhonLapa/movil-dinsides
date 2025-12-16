import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'location_service.dart';
import 'live_map_viewer.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ChatScreen extends StatefulWidget {
  final String idConversacion;
  final String idPedido;
  final String miId;
  final String miTipo;

  const ChatScreen({
    super.key,
    required this.idConversacion,
    required this.idPedido,
    required this.miId,
    required this.miTipo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final String _chatCollectionPath =
      'chats/${widget.idConversacion}/mensajes';

  String? _miIdEnChat;
  String? _interlocutorId;
  String? _interlocutorNombre;
  String? _interlocutorFotoUrl;
  String? _liveSessionId;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChatData();
  }

  Future<String?> subirImagenAServidor(String pathLocal) async {
    final url = Uri.parse(
      "https://test.dinsidescourier.com/api_subir_foto_chat.php",
    );

    var request = http.MultipartRequest("POST", url);
    request.files.add(await http.MultipartFile.fromPath("foto", pathLocal));

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);

      if (data["success"] == true) {
        return data["url"]; // URL de Cloudflare R2
      } else {
        print("Error servidor: ${data["message"]}");
        return null;
      }
    } catch (e) {
      print("Error al subir imagen: $e");
      return null;
    }
  }

  Future<void> _loadChatData() async {
    try {
      final urlString =
          'https://test.dinsidescourier.com/get_chat_info.php?id_conversacion=${widget.idConversacion}&mi_id=${widget.miId}&mi_tipo=${widget.miTipo}';

      final url = Uri.parse(urlString);
      final response = await http.get(url).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true) {
          final data = jsonResponse['data'];

          setState(() {
            _miIdEnChat = data['yo']['id'].toString();
            _interlocutorId = data['interlocutor']['id'].toString();
            _interlocutorNombre = data['interlocutor']['nombre'];
            _interlocutorFotoUrl = data['interlocutor']['foto_url'];
          });

          _marcarMensajesComoVistos();
        }
      }
    } catch (e) {
      print("Error cargando chat: $e");
    }

    setState(() => _isLoading = false);
  }

  void _marcarMensajesComoVistos() async {
    if (_miIdEnChat == null) return;

    final snap = await _firestore
        .collection(_chatCollectionPath)
        .where('receptorId', isEqualTo: _miIdEnChat)
        .where('estado', isNotEqualTo: 'visto')
        .get();

    final batch = _firestore.batch();
    for (var doc in snap.docs) {
      batch.update(doc.reference, {'estado': 'visto'});
    }
    await batch.commit();
  }

  Future<void> _sendTextMessage(String text) async {
    if (text.trim().isEmpty || _miIdEnChat == null) return;

    await _firestore.collection(_chatCollectionPath).add({
      'emisorId': _miIdEnChat,
      'receptorId': _interlocutorId,
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': 'texto',
      'contenido': text.trim(),
      'estado': 'enviado',
    });

    _controller.clear();
  }

  Future<void> _enviarImagen(String localPath) async {
    final urlImagen = await subirImagenAServidor(localPath);

    if (urlImagen == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Error subiendo imagen")));
      }
      return;
    }

    await _firestore.collection(_chatCollectionPath).add({
      'emisorId': _miIdEnChat,
      'receptorId': _interlocutorId,
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': 'imagen',
      'contenido': urlImagen,
      'estado': 'enviado',
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: source);

    if (picked != null) {
      await _enviarImagen(picked.path);
    }
  }

  Future<void> _enviarUbicacionActual() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("El GPS está desactivado")),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permisos de ubicación denegados")),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Los permisos están bloqueados permanentemente"),
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Obteniendo ubicación...")));
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    String locationString = "${position.latitude},${position.longitude}";

    await _firestore.collection(_chatCollectionPath).add({
      'emisorId': _miIdEnChat,
      'receptorId': _interlocutorId,
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': 'ubicacion',
      'contenido': locationString,
      'estado': 'enviado',
    });
  }

  Future<void> _iniciarUbicacionEnTiempoReal() async {
  // 1. Permisos de ubicación
  final loc = await Permission.location.request();
  if (!loc.isGranted) return;

  final always = await Permission.locationAlways.request();
  if (!always.isGranted) {
    if (mounted) openAppSettings();
    return;
  }

  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  }

  // 2. Ubicación inicial
  final position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  // 3. SessionId único
  final sessionId =
      "${widget.idConversacion}_${DateTime.now().millisecondsSinceEpoch}";

  // 4. Firestore inicial (Estado: initializing)
  await _firestore.collection('active_locations').doc(sessionId).set({
    'latitude': position.latitude,
    'longitude': position.longitude,
    'heading': position.heading,
    'speed': position.speed,
    'status': 'initializing', // Importante para que el mapa sepa que estamos cargando
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // 5. Servicio Background
  final service = FlutterBackgroundService();

  // Si NO está corriendo, pedimos permisos y lo iniciamos
  if (!await service.isRunning()) {
    // --- TU CÓDIGO DE PERMISOS (Android 13+) ---
    if (Platform.isAndroid) {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt >= 33) {
        final notif = await Permission.notification.request();
        if (!notif.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Permiso de notificaciones requerido")),
            );
          }
          return;
        }
      }
    }

    // --- AQUÍ ARRANCAMOS EL SERVICIO ---
    await service.startService();
    
    // 🛑 IMPORTANTE: Esperamos 4 segundos para que el servicio cargue bien en el emulador
    print("⏳ Esperando arranque del servicio...");
    await Future.delayed(const Duration(seconds: 4)); 
  }

  // 6. 🔥 EL BOMBARDEO (Solución al "Conectando...") 🔥
  // Enviamos el ID 10 veces para asegurar que el servicio lo escuche
  print("📡 ENVIANDO ID AL BACKGROUND...");
  for (int i = 0; i < 10; i++) { 
    service.invoke("startTracking", {"sessionId": sessionId});
    print("   -> Intento #$i enviado");
    await Future.delayed(const Duration(milliseconds: 800)); // Pausa entre intentos
  }

  // 7. Mensaje al chat
  await _firestore.collection(_chatCollectionPath).add({
    'emisorId': _miIdEnChat,
    'receptorId': _interlocutorId,
    'timestamp': FieldValue.serverTimestamp(),
    'tipo': 'live_location',
    'contenido': sessionId,
    'estado': 'enviado',
  });

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ubicación en tiempo real compartida")),
    );
  }

  // 8. Auto-stop seguro (15 min)
  Future.delayed(const Duration(minutes: 15), () async {
    service.invoke("stopService");
    await _firestore.collection('active_locations').doc(sessionId).set({
      'status': 'finished',
    }, SetOptions(merge: true));
  });
}

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // Fondo limpio
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pequeña línea decorativa arriba
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              title: const Text("Galería"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.pink,
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
              title: const Text("Cámara"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const Divider(), // Separador elegante
            // OPCIÓN 1: UBICACIÓN FIJA
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.location_on, color: Colors.white, size: 20),
              ),
              title: const Text("Enviar ubicación actual"),
              subtitle: const Text("Punto fijo"),
              onTap: () {
                Navigator.pop(context);
                _enviarUbicacionActual();
              },
            ),

            // OPCIÓN 2: EN TIEMPO REAL (¡LA QUE FALTABA!)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent, // Color destacado
                child: Icon(
                  Icons.directions_bike,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: const Text("Compartir trayecto en vivo"),
              subtitle: const Text("Visible por 15 min"),
              trailing: const Icon(Icons.timelapse, color: Colors.blueAccent),
              onTap: () {
                // NO cierres el navigator aquí, la función maneja sus diálogos
                _iniciarUbicacionEnTiempoReal();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ======================================
  // 🔥 UI COMPLETA
  // ======================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Cargando...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(
                _interlocutorFotoUrl ?? "https://i.imgur.com/d1h7XhI.png",
              ),
            ),
            const SizedBox(width: 10),
            Text(_interlocutorNombre ?? "Chat"),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection(_chatCollectionPath)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final mensajes = snap.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: mensajes.length,
                  itemBuilder: (_, i) {
                    final msg = mensajes[i].data() as Map<String, dynamic>;

                    return BubbleMessage(
                      contenido: msg['contenido'],
                      tipo: msg['tipo'],
                      isMe: msg['emisorId'] == _miIdEnChat,
                      time: (msg['timestamp'] as Timestamp?)?.toDate(),
                      estado: msg['estado'] ?? 'enviado',
                    );
                  },
                );
              },
            ),
          ),
          _chatInput(),
        ],
      ),
    );
  }

  Widget _chatInput() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.blue),
            onPressed: _showImageOptions,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: _sendTextMessage,
              decoration: InputDecoration(
                hintText: "Escribe un mensaje",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          FloatingActionButton(
            mini: true,
            onPressed: () => _sendTextMessage(_controller.text),
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class BubbleMessage extends StatelessWidget {
  final String contenido;
  final String tipo;
  final bool isMe;
  final DateTime? time;
  final String estado;

  const BubbleMessage({
    super.key,
    required this.contenido,
    required this.tipo,
    required this.isMe,
    this.time,
    required this.estado,
  });

  // CORRECCIÓN: Agregamos (BuildContext context) como parámetro
  Future<void> _abrirMapa(BuildContext context) async {
    final coords = contenido.split(",");

    if (coords.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ubicación en tiempo real (Ver en mapa)")),
      );
      return;
    }

    // Definimos lat y lng
    final lat = coords[0].trim();
    final lng = coords[1].trim();

    // Usamos las variables en la URL
    final googleMapsUrl = Uri.parse(
      "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
    );

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      // Usamos el context que recibimos
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No se pudo abrir el mapa")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipoLimpio = tipo.trim().toLowerCase();
    final esImagen = tipoLimpio == "imagen";
    final esUbicacion = tipoLimpio == "ubicacion";
    final esLive = tipoLimpio == "live_location";

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: esImagen || esUbicacion || esLive
            ? const EdgeInsets.all(4)
            : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. SI ES IMAGEN
            if (esImagen)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  contenido,
                  width: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 40),
                ),
              )
            // 2. SI ES UBICACIÓN (FIJA O LIVE)
            else if (esUbicacion || esLive)
              GestureDetector(
                onTap: () {
                  if (esLive) {
                    // Aquí iría la navegación al mapa en vivo
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LiveMapViewer(sessionId: contenido),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Abriendo mapa en vivo...")),
                    );
                  } else {
                    // CORRECCIÓN: Pasamos el context aquí
                    _abrirMapa(context);
                  }
                },
                child: Container(
                  width: 220,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: esLive
                          ? [Colors.blue[700]!, Colors.blue[400]!]
                          : [Colors.amber[100]!, Colors.orange[50]!],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        bottom: -20,
                        child: Icon(
                          esLive ? Icons.directions_bike : Icons.map,
                          size: 100,
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 25,
                              child: Icon(
                                esLive
                                    ? Icons.share_location
                                    : Icons.location_on,
                                color: esLive ? Colors.blue : Colors.red,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              esLive ? "Ubicación en Tiempo Real" : "Ubicación",
                              style: TextStyle(
                                color: esLive
                                    ? Colors.white
                                    : Colors.brown[800],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (esLive)
                              Container(
                                margin: const EdgeInsets.only(top: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  "EN VIVO",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            // 3. SI ES TEXTO
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(contenido, style: const TextStyle(fontSize: 16)),
              ),

            // FECHA Y CHECKS
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time != null ? DateFormat("HH:mm").format(time!) : "",
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  if (isMe)
                    Icon(
                      estado == "visto" ? Icons.done_all : Icons.done,
                      size: 16,
                      color: estado == "visto" ? Colors.blue : Colors.grey,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
