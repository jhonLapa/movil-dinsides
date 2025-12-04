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
      final urlString = 'https://test.dinsidescourier.com/get_chat_info.php?id_conversacion=${widget.idConversacion}&mi_id=${widget.miId}&mi_tipo=${widget.miTipo}';

      final url = Uri.parse(urlString);
      
      final response = await http.get(url).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];

          setState(() {
            _miIdEnChat = data['yo']['id']?.toString();
            
            _interlocutorId = data['interlocutor']['id']?.toString();
            _interlocutorNombre = data['interlocutor']['nombre'];
            _interlocutorFotoUrl = data['interlocutor']['foto_url'];
            
            _idPedidoContexto = data['id_pedido']?.toString(); 
          });

          _marcarMensajesComoVistos();

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

  void _marcarMensajesComoVistos() async {
    if (_miIdEnChat == null) return;

    try {
      final snapshot = await _firestore.collection(_chatCollectionPath)
          .where('receptorId', isEqualTo: _miIdEnChat)
          .where('estado', isNotEqualTo: 'visto')
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'estado': 'visto'});
      }
      await batch.commit();
    } catch (e) {
      print("Nota: Si sale error de índice, crea el índice en Firebase Console (Link en logs). Error: $e");
    }
  }

  void _sendMessage({String? texto, String? localImagePath}) async {
    final content = texto?.trim();
    if ((content == null || content.isEmpty) && localImagePath == null) return;

    if (_miIdEnChat == null) {
      print("Error: IDs no cargados.");
      return;
    }

    final nuevoMensaje = {
      'emisorId': _miIdEnChat.toString(),
      'receptorId': _interlocutorId.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'tipo': localImagePath != null ? 'imagen_local' : 'texto',
      'contenido': localImagePath ?? content,
      'estado': 'enviado', 
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
          content: const Text('¿Estás seguro de que deseas eliminar todos los mensajes?'),
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
      final QuerySnapshot snapshot = await _firestore.collection(_chatCollectionPath).get();
      final WriteBatch batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historial eliminado.')));
      }
    } catch (e) {
      print('Error al eliminar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cargando...'), backgroundColor: Colors.blue),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _interlocutorNombre == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.red, title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: ${_errorMessage ?? "Datos incompletos."}'),
              ElevatedButton(onPressed: _loadChatData, child: const Text('Reintentar'))
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(_interlocutorFotoUrl ?? 'https://i.imgur.com/d1h7XhI.png'),
              radius: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _interlocutorNombre!,
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
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection(_chatCollectionPath)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                  final messages = snapshot.data!.docs;
                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final data = message.data() as Map<String, dynamic>;

                      final isMe = data['emisorId'].toString() == _miIdEnChat;
                      
                      return BubbleMessage(
                        contenido: data['contenido'] ?? '',
                        tipo: data['tipo'] ?? 'texto',
                        isMe: isMe,
                        time: (data['timestamp'] as Timestamp?)?.toDate(),
                        // 🔥 Pasamos el estado al widget visual
                        estado: data['estado'] ?? 'enviado', 
                      );
                    },
                  );
                },
              ),
            ),
          ),
          // Input
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (text) => _sendMessage(texto: text),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: () => _sendMessage(texto: _controller.text),
                  mini: true,
                  backgroundColor: Colors.blue, // Botón Azul
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
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
    this.estado = 'enviado', 
  });

  Widget _buildMessageContent(BuildContext context) {
    if (tipo == 'imagen_local' || tipo == 'imagen') {
      // Imagen
      return Container(
        constraints: const BoxConstraints(maxWidth: 250),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: tipo == 'imagen_local'
              ? Image.file(File(contenido), fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image))
              : Image.network(
                  contenido,
                  loadingBuilder: (ctx, child, progress) => progress == null ? child : const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()),
                  errorBuilder: (_,__,___) => const Icon(Icons.error),
                ),
        ),
      );
    } else {
      // Texto normal
      return Text(contenido, style: const TextStyle(fontSize: 16));
    }
  }

  Widget _buildStatusIcon() {
    if (!isMe) return const SizedBox.shrink(); 

    IconData icon = Icons.done; 
    Color color = Colors.grey;

    if (estado == 'visto') {
      icon = Icons.done_all; 
      color = Colors.blue;   
    } else if (estado == 'recibido') {
      icon = Icons.done_all; 
      color = Colors.grey;   
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Icon(icon, size: 16, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeString = time == null ? '' : DateFormat('HH:mm').format(time!);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white, 
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end, 
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMessageContent(context),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(timeString, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                _buildStatusIcon(), 
              ],
            ),
          ],
        ),
      ),
    );
  }
}