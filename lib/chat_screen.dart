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

  late final String _chatCollectionPath = 'chats/${widget.idConversacion}/mensajes';

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

  Future<void> _loadChatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // URL de tu servidor
      final urlString = 'http://10.0.2.2/dinsidescourier/get_chat_info.php?id_conversacion=${widget.idConversacion}&mi_id=${widget.miId}&mi_tipo=${widget.miTipo}';
      final url = Uri.parse(urlString);
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Decodificamos la respuesta JSON
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];

          setState(() {
            // Convertimos a String para evitar errores de tipo en Firebase
            _miIdEnChat = data['yo']['id']?.toString();
            
            _interlocutorId = data['interlocutor']['id']?.toString();
            _interlocutorNombre = data['interlocutor']['nombre'];
            _interlocutorFotoUrl = data['interlocutor']['foto_url'];
            
            _idPedidoContexto = data['id_pedido_contexto']?.toString();
          });
        } else {
          throw Exception('API Error: ${jsonResponse['message']}');
        }
      } else {
        throw Exception('Error de red: ${response.statusCode}');
      }
    } catch (e) {
      print('Error al cargar datos del chat: $e');
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sendMessage({String? texto, String? localImagePath}) async {
    final content = texto?.trim();
    if ((content == null || content.isEmpty) && localImagePath == null) return;

    if (_miIdEnChat == null) {
      print("Error: IDs no cargados, no se puede enviar mensaje.");
      return;
    }

    final nuevoMensaje = {
      'emisorId': _miIdEnChat.toString(), // Aseguramos String
      'receptorId': _interlocutorId.toString(), // Aseguramos String
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': localImagePath != null ? 'imagen_local' : 'texto',
      'contenido': localImagePath ?? content,
    };

    try {
      await _firestore.collection(_chatCollectionPath).add(nuevoMensaje);
      _controller.clear();
    } catch (e) {
      print('Error al enviar mensaje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando mensaje: $e')),
      );
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        _sendMessage(localImagePath: pickedFile.path);
      }
    } catch (e) {
      print("Error al seleccionar imagen: $e");
    }
  }

  Future<void> _eliminarHistorialChat() async {
    final bool confirmar = await showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Confirmar Eliminación'),
          content: const Text(
              '¿Estás seguro de que deseas eliminar todos los mensajes?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            TextButton(
              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      final QuerySnapshot snapshot =
          await _firestore.collection(_chatCollectionPath).get();

      final WriteBatch batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Historial eliminado.')));
      }
    } catch (e) {
      print('Error al eliminar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Pantalla de carga inicial (mientras busca datos en PHP)
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cargando Chat...'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Pantalla de Error (si PHP falló)
    if (_errorMessage != null || _interlocutorNombre == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.red, title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Error al cargar el chat:\n${_errorMessage ?? "Datos incompletos."}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loadChatData,
                  child: const Text('Reintentar'),
                )
              ],
            ),
          ),
        ),
      );
    }

    // 3. Pantalla de Chat (Correcta)
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(
                    _interlocutorFotoUrl ?? 'https://i.imgur.com/d1h7XhI.png'),
                radius: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat con $_interlocutorNombre',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_idPedidoContexto != null)
                      Text(
                        'Pedido #$_idPedidoContexto',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
              onPressed: _eliminarHistorialChat,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Container(
                color: const Color(0xFFE5DDD5),
                // ⭐⭐ CORRECCIÓN DEL STREAM BUILDER PARA CARGA INFINITA ⭐⭐
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection(_chatCollectionPath)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Si no hay mensajes aún
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay mensajes aún.\n¡Escribe el primero!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    final messages = snapshot.data!.docs;
                    return ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final data = message.data() as Map<String, dynamic>;

                        final isMe = data['emisorId'].toString() == _miIdEnChat;
                        final tipo = data['tipo'] ?? 'texto';
                        final contenido = data['contenido'] ?? '';

                        return BubbleMessage(
                          contenido: contenido,
                          isMe: isMe,
                          tipo: tipo,
                          time: (data['timestamp'] as Timestamp?)?.toDate(),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            // Área de Input
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.blue),
                    onPressed: _showImageSourceActionSheet,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      onSubmitted: (text) => _sendMessage(texto: text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: () => _sendMessage(texto: _controller.text),
                    mini: true,
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.send, color: Colors.white),
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

// Widget de la burbuja de chat
class BubbleMessage extends StatelessWidget {
  final String contenido;
  final String tipo;
  final bool isMe;
  final DateTime? time;

  const BubbleMessage({
    super.key,
    required this.contenido,
    required this.tipo,
    required this.isMe,
    this.time,
  });

  Widget _buildMessageContent(BuildContext context) {
    if (tipo == 'imagen_local' || tipo == 'imagen') {
      // Si es local (File)
      if (tipo == 'imagen_local') {
        return Container(
          constraints: const BoxConstraints(maxWidth: 250),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(contenido),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image, color: Colors.red),
            ),
          ),
        );
      }
      // Si es red (Network)
      return Container(
        constraints: const BoxConstraints(maxWidth: 250),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            contenido,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.error, color: Colors.red),
          ),
        ),
      );
    } else {
      return Text(contenido, style: const TextStyle(fontSize: 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeString = time == null ? '' : DateFormat('HH:mm').format(time!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: isMe
                    ? null
                    : const [BoxShadow(color: Colors.black12, blurRadius: 1)],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildMessageContent(context),
                    const SizedBox(height: 3),
                    Text(timeString,
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}