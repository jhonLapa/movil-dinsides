import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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
  String? _interlocutorNombre;
  String? _interlocutorFotoUrl;
  String? _interlocutorId;
  String? _idPedidoContexto;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChatData();
  }

  // ======================================
  // 🔥 SUBIR IMAGEN A TU API PHP + R2
  // ======================================
  Future<String?> subirImagenAServidor(String pathLocal) async {
    final url =
        Uri.parse("https://test.dinsidescourier.com/api_subir_foto_chat.php");

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

  // ======================================
  // 🔥 CARGAR INFO DEL CHAT
  // ======================================
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
            _idPedidoContexto = data['id_pedido'].toString();
          });

          _marcarMensajesComoVistos();
        }
      }
    } catch (e) {
      _errorMessage = "Error cargando chat: $e";
    }

    setState(() => _isLoading = false);
  }

  // ======================================
  // 🔥 MARCAR MENSAJES COMO VISTOS
  // ======================================
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

  // ======================================
  // 🔥 ENVIAR MENSAJE TEXTO
  // ======================================
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

  // ======================================
  // 🔥 ENVIAR IMAGEN
  // ======================================
  Future<void> _enviarImagen(String localPath) async {
    final urlImagen = await subirImagenAServidor(localPath);

    if (urlImagen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error subiendo imagen")),
      );
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

  // ======================================
  // 🔥 SELECCIONAR IMAGEN
  // ======================================
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: source);

    if (picked != null) {
      await _enviarImagen(picked.path);
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Galería"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Cámara"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
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
                    final msg =
                        mensajes[i].data() as Map<String, dynamic>;

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
          )
        ],
      ),
    );
  }
}

// ======================================
// 🔥 WIDGET DE BURBUJA (CORREGIDO)
// ======================================
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

  @override
  Widget build(BuildContext context) {
    final tipoLimpio = tipo.trim().toLowerCase();
    final esImagen =
        tipoLimpio == "imagen" || tipoLimpio == "imagen_local";

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.green[100] : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            esImagen
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      contenido,
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 40),
                    ),
                  )
                : Text(
                    contenido,
                    style: const TextStyle(fontSize: 16),
                  ),

            const SizedBox(height: 3),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time != null ? DateFormat("HH:mm").format(time!) : "",
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                if (isMe)
                  Icon(
                    estado == "visto" ? Icons.done_all : Icons.done,
                    size: 16,
                    color: estado == "visto" ? Colors.blue : Colors.grey,
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
